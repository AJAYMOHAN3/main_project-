const { setGlobalOptions } = require("firebase-functions/v2"); // <--- Added this
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");const admin = require("firebase-admin");
admin.initializeApp();
setGlobalOptions({ region: "asia-south1" });
exports.notifyOnRequestAccepted = onDocumentUpdated("trequests/{tenantId}", async (event) => {
  const tenantId = event.params.tenantId;

  // Get the old array and the new array
  const beforeRequests = event.data.before.data().requests || [];
  const afterRequests = event.data.after.data().requests || [];

  // Figure out which specific request changed
  let newlyAcceptedRequest = null;

  for (let i = 0; i < afterRequests.length; i++) {
    const afterReq = afterRequests[i];
    const beforeReq = beforeRequests[i];

    // Check if status changed from 'pending' to 'accepted'
    if (
      afterReq.status === "accepted" &&
      (!beforeReq || beforeReq.status === "pending")
    ) {
      newlyAcceptedRequest = afterReq;
      break;
    }
  }

  // If nothing changed to accepted, stop the function
  if (!newlyAcceptedRequest) {
    return null;
  }

  // 1. Get the tenant's FCM token from their profile
  const tenantDoc = await admin.firestore().collection("tenant").doc(tenantId).get();
  const tenantData = tenantDoc.data();
  
  if (!tenantData || !tenantData.fcmToken) {
    console.log("No FCM token found for user:", tenantId);
    return null;
  }

  // 2. Build the notification payload
  const message = {
    notification: {
      title: "Request Accepted!",
      body: `Your request for ${newlyAcceptedRequest.apartmentName} was accepted by ${newlyAcceptedRequest.landlordName}. Please complete your payment.`,
    },
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      type: "payment_due",
      luid: newlyAcceptedRequest.luid || ""
    },
    token: tenantData.fcmToken
  };

  // 3. Send the push notification
  try {
    const response = await admin.messaging().send(message);
    console.log("Notification sent successfully:", response);
  } catch (error) {
    console.error("Error sending notification:", error);
  }

  return null;
});