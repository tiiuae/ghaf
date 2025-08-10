# About
TII SSRC Secure Technologies: Shared Memory Socket Forwarder
The Shared Memory Sockets Proxy (shmsockproxy) is a communication mechanism between guest virtual machines.

This tool forwards socket connections between two guest VMs to enable Waypipe communication.

It listens for incoming connections on one VM's socket, creates a connection to the other VM's socket, and forwards 
data in both directions.
On the server (application) VM side, it creates a socket that Waypipe connects to. All data coming from/to the Waypipe socket 
is forwarded to/from the client VM side using a shared memory mechanism.
On the client (display) VM side, the shmsockproxy connects to Waypipe's existing socket and forwards data to/from the 
connected server (application) VM side.

The tool consists of:
- A shared memory kernel driver (ivshmem.c), which creates the /dev/ivshmem device and handles typical I/O functions (open,
  close, ioctl, mmap, read, write).
- A socket forwarding application.

# Building

# Usage
