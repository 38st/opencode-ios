// The delivery logic is shared with the plugin's direct mode (server/contracts/src/apns.ts).
export {
  apnsPath, deliver, mapResponse,
  type ApnsResponse, type ApnsSender, type Delivery, type DeliveryResult,
} from "../../../contracts/src/apns.ts";
