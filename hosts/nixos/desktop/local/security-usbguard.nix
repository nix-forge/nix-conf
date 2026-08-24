{ lib, ... }: {
  security.usbguardBaseline.enable = true;

  services.usbguard = {
    # This immutable policy was generated on 2026-08-24 with:
    #   usbguard generate-policy -p -H
    # on this desktop, then reviewed. Each permanent device is pinned to its
    # full descriptor hash, parent topology, and physical port. Regenerate and
    # review it after a motherboard/peripheral firmware change or hardware move;
    # do not add broad vendor-ID allow rules.
    #
    # The currently attached Samsung Flash Drive FIT (090c:1000) is deliberately
    # absent. Removable mass storage is blocked by default. If it becomes a
    # trusted, permanently attached recovery device, add a reviewed hash-and-
    # port rule here.
    rules = ''
      allow hash "+Lsm3uXJrL0KwWr8E3Phv/ov65s/QLIBmiqongfUTzc=" parent-hash "5y2DlcZbTmr7Ngt3QG2uXCzlOxQh9Dekr4t0aSdW5r8=" via-port "usb1"
      allow hash "B+IrGjLNXzR9fYfVYum8R3oPcPVtyThrRFVOQpVbq+A=" parent-hash "5y2DlcZbTmr7Ngt3QG2uXCzlOxQh9Dekr4t0aSdW5r8=" via-port "usb2"
      allow hash "zxDBh/963aknmw5aLkP+8p3IY8APWe2T5A3OAdEsrTw=" parent-hash "ULhS/QsA5Sv9/5t6D/3RbOjxJ/0h2MzQkBeHhoLbv6M=" via-port "usb3"
      allow hash "vrA/WXTjDhXEUz50FSN51k/hyBy1DebU9tBpMQMiPtc=" parent-hash "ULhS/QsA5Sv9/5t6D/3RbOjxJ/0h2MzQkBeHhoLbv6M=" via-port "usb4"
      allow hash "ZSIwGrd3P5OijFEKFFRXtBKibyl6VwegRhsvNUTUBeo=" parent-hash "EtBRf2trbghR8phOdMMolypXS41s9dammNzThp2IG6g=" via-port "usb5"
      allow hash "WsWOWC2Sd9MdaR8y3kCnZnbsGRF7Is9LR2iaMqR4kAo=" parent-hash "EtBRf2trbghR8phOdMMolypXS41s9dammNzThp2IG6g=" via-port "usb6"
      allow hash "9guzk92U3kBrO5xnDc5EZ48BED+SzMBbWCsJ8J1PBkI=" parent-hash "1V/z+1NKyXY+K9p99IvqdU537fu3/V4sJ8pXj3HPZrQ=" via-port "usb7"
      allow hash "3diggCc+UIkz1I9skI/9PxceyT0kr5r7GL5FqNeqFZg=" parent-hash "+Lsm3uXJrL0KwWr8E3Phv/ov65s/QLIBmiqongfUTzc=" via-port "1-5"
      allow hash "kL7WFVC+wRu2UhoA7qb7Ga7AhIMyAuHfB4xoYj5eFDA=" parent-hash "+Lsm3uXJrL0KwWr8E3Phv/ov65s/QLIBmiqongfUTzc=" via-port "1-6"
      allow hash "eM73IFKY9T4ydP+CKuo6KEp/Fhrl72VFzccohhOSiRg=" parent-hash "+Lsm3uXJrL0KwWr8E3Phv/ov65s/QLIBmiqongfUTzc=" via-port "1-7"
      allow hash "djeL7wNsJBQMuBiqUyWflgupndhsbPkbOih8g3L6OeA=" parent-hash "+Lsm3uXJrL0KwWr8E3Phv/ov65s/QLIBmiqongfUTzc=" via-port "1-8"
      allow hash "u+NgVC10sqnPD0Rf2fZCa9joVQ4VZhizQq2ArhktmFg=" parent-hash "B+IrGjLNXzR9fYfVYum8R3oPcPVtyThrRFVOQpVbq+A=" via-port "2-5"
      allow hash "qqBDnch40pQanNtd1/OKs1hW6z/MX+m4FBV68ZN1Tk0=" parent-hash "+Lsm3uXJrL0KwWr8E3Phv/ov65s/QLIBmiqongfUTzc=" via-port "1-10"
      allow hash "W6l+xvpLKIN6p2T3tTOGGy7Qm+zPESG43Fox/qV9OCE=" parent-hash "+Lsm3uXJrL0KwWr8E3Phv/ov65s/QLIBmiqongfUTzc=" via-port "1-12"
    '';

  };

  # Select this systemd-boot specialisation if a changed descriptor or local
  # policy prevents a necessary HID device from working. It removes only
  # USBGuard; the normal boot entry remains the secure default.
  specialisation.usbguard-recovery.configuration = {
    security.usbguardBaseline.enable = lib.mkForce false;
    services.usbguard.enable = lib.mkForce false;
  };
}
