# TouchDesigner quick connection examples

The iPhone app does not hard-code a computer address. Enter the address that is reachable from the phone.

## WebSocket
Use a TouchDesigner Web Server DAT / WebSocket-capable component or a small local bridge and enter for example:

`ws://192.168.1.50:9980`

## HTTP
For an HTTP listener or local bridge:

`http://192.168.1.50:8080/event`

## UDP
Enter the computer host and UDP port, then send arbitrary UTF-8 text.

## OSC
Enter the same host/port, an OSC address such as `/iphone/value`, and one string value. The V2 client encodes a standards-compatible OSC string message.

A Tailscale IP can be used instead of the LAN IP when the target service listens on that interface and local firewall rules allow it.
