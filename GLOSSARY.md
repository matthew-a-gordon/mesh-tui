# Mesh TUI

A keyboard-only terminal client for Meshtastic mesh networks, built for the ClockworkPi uConsole.

## Language

**Mesh**:
The set of Meshtastic radios that can hear each other and relay one another's packets.
_Avoid_: Network, net

**Node**:
One radio on the Mesh, identified by a node number and shown by its short and long names.
_Avoid_: Device, radio, contact, station

**Local Node**:
The Node this client is connected to and acts through.
_Avoid_: Host, my radio

**Channel**:
A named, keyed group conversation on the Mesh that the Local Node is configured to send and receive on.
_Avoid_: Room, group

**Message**:
A text sent to a Channel or to a single Node.
_Avoid_: Packet, chat

**Direct Message**:
A Message addressed to one Node instead of a Channel.
_Avoid_: DM, private message

**Traceroute**:
A request that reports the hops a packet takes between the Local Node and another Node.
_Avoid_: Ping, route test

**Telemetry**:
Periodic readings a Node reports about itself, such as battery and environment sensors.
_Avoid_: Stats, metrics
