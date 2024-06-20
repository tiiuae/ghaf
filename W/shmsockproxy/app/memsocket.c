/* Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
   SPDX-License-Identifier: Apache-2.0
*/
#include <arpa/inet.h>
#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/poll.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include "../drivers/char/ivshmem/kvm_ivshmem.h"

#ifndef VM_COUNT
#define VM_COUNT (5)
#endif

#define SHM_DEVICE_FN "/dev/ivshmem"

#define MAX_EVENTS (1024)
#define MAX_CLIENTS (10)
#define BUFFER_SIZE (1024000)
#define SHMEM_POLL_TIMEOUT (3000)
#define SHMEM_BUFFER_SIZE (1024000)
#define UNKNOWN_PEER (-1)
#define CLOSE_FD (1)
#define IGNORE_ERROR (1)
#define PAGE_SIZE (32)

#define DBG(fmt, ...)                                                          \
  {                                                                            \
    char tmp1[512], tmp2[256];                                                 \
    sprintf(tmp2, fmt, __VA_ARGS__);                                           \
    sprintf(tmp1, "[%d] %s:%d: %s\n", instance_no, __FUNCTION__, __LINE__,     \
            tmp2);                                                             \
    errno = 0;                                                                 \
    report(tmp1, 0);                                                           \
  }

#ifndef DEBUG_ON
#define DEBUG(fmt, ...)                                                        \
  {}
#else
#define DEBUG DBG
#endif

#ifndef DEBUG_ON
#define INFO(fmt, ...)                                                         \
  {}
#else
#define INFO(fmt, ...)                                                         \
  {                                                                            \
    char tmp1[512], tmp2[256];                                                 \
    sprintf(tmp2, fmt, __VA_ARGS__);                                           \
    sprintf(tmp1, "[%d] [%s:%d] %s\n", instance_no, __FUNCTION__, __LINE__,    \
            tmp2);                                                             \
    errno = 0;                                                                 \
    report(tmp1, 0);                                                           \
  }
#endif

#define ERROR0(msg)                                                            \
  {                                                                            \
    char tmp[512];                                                             \
    sprintf(tmp, "[%d] [%s:%d] %s\n", instance_no, __FUNCTION__, __LINE__,     \
            msg);                                                              \
    report(tmp, 0);                                                            \
  }

#define ERROR(fmt, ...)                                                        \
  {                                                                            \
    char tmp1[512], tmp2[256];                                                 \
    sprintf(tmp2, fmt, __VA_ARGS__);                                           \
    sprintf(tmp1, "[%d] [%s:%d] %s\n", instance_no, __FUNCTION__, __LINE__,    \
            tmp2);                                                             \
    report(tmp1, 0);                                                           \
  }

#define FATAL(msg)                                                             \
  {                                                                            \
    char tmp1[512], tmp2[256];                                                 \
    sprintf(tmp2, msg);                                                        \
    sprintf(tmp1, "[%d] [%s:%d]: %s\n", instance_no, __FUNCTION__, __LINE__,   \
            tmp2);                                                             \
    report(tmp1, 1);                                                           \
  }

enum { CMD_LOGIN, CMD_CONNECT, CMD_DATA, CMD_CLOSE, CMD_DATA_CLOSE };
#define FD_MAP_COUNT (sizeof(fd_map) / sizeof(fd_map[0]))
struct {
  int my_fd;
  int remote_fd;
} fd_map[VM_COUNT][MAX_CLIENTS];

typedef struct {
  volatile int server_vmid;
  volatile int cmd;
  volatile int fd;
  volatile int len;
  volatile unsigned char data[SHMEM_BUFFER_SIZE];
} vm_data;

int epollfd_full[VM_COUNT], epollfd_limited[VM_COUNT];
char *socket_path;
int server_socket = -1, shmem_fd[VM_COUNT];
volatile int *my_vmid = NULL;
vm_data *my_shm_data[VM_COUNT], *peer_shm_data[VM_COUNT];
int run_as_server = 0;
int local_rr_int_no[VM_COUNT], remote_rc_int_no[VM_COUNT];
pthread_t server_threads[VM_COUNT];
struct {
  volatile int client_vmid;
  vm_data client_data[VM_COUNT];
  vm_data server_data[VM_COUNT];
} *vm_control;

static const char usage_string[] = "Usage: memsocket [-c|-s] socket_path "
                                   "{instance number (server mode only)}\n";

void report(const char *msg, int terminate) {

  if (errno)
    perror(msg);
  else
    fprintf(stderr, "%s", msg);

  if (terminate)
    exit(-1);
}

int get_shmem_size(int instance_no) {

  int res;

  res = lseek(shmem_fd[instance_no], 0, SEEK_END);
  if (res < 0) {
    FATAL("seek");
  }
  lseek(shmem_fd[instance_no], 0, SEEK_SET);
  return res;
}

void fd_map_clear(int instance_no) {

  int i;

  for (i = 0; i < MAX_CLIENTS; i++) {
    fd_map[instance_no][i].my_fd = -1;
    fd_map[instance_no][i].remote_fd = -1;
  }
}

void server_init(int instance_no) {

  struct sockaddr_un socket_name;
  struct epoll_event ev;

  /* Remove socket file if exists */
  if (access(socket_path, F_OK) == 0) {
    remove(socket_path);
  }

  server_socket = socket(AF_UNIX, SOCK_STREAM, 0);
  if (server_socket < 0) {
    FATAL("server socket");
  }

  DEBUG("server socket: %d", server_socket);

  memset(&socket_name, 0, sizeof(socket_name));
  socket_name.sun_family = AF_UNIX;
  strncpy(socket_name.sun_path, socket_path, sizeof(socket_name.sun_path) - 1);
  if (bind(server_socket, (struct sockaddr *)&socket_name,
           sizeof(socket_name)) < 0) {
    FATAL("bind");
  }

  if (listen(server_socket, MAX_EVENTS) < 0)
    FATAL("listen");

  ev.events = EPOLLIN;
  ev.data.fd = server_socket;
  if (epoll_ctl(epollfd_full[instance_no], EPOLL_CTL_ADD, server_socket, &ev) ==
      -1) {
    FATAL("server_init: epoll_ctl: server_socket");
  }

  INFO("server initialized", "");
}

int wayland_connect(int instance_no) {

  struct sockaddr_un socket_name;
  struct epoll_event ev;
  int wayland_fd;

  wayland_fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (wayland_fd < 0) {
    FATAL("wayland socket");
  }

  DEBUG("wayland socket: %d", wayland_fd);

  memset(&socket_name, 0, sizeof(socket_name));
  socket_name.sun_family = AF_UNIX;
  strncpy(socket_name.sun_path, socket_path, sizeof(socket_name.sun_path) - 1);
  if (connect(wayland_fd, (struct sockaddr *)&socket_name,
              sizeof(socket_name)) < 0) {
    FATAL("connect");
  }

  ev.events = EPOLLIN;
  ev.data.fd = wayland_fd;
  if (epoll_ctl(epollfd_full[instance_no], EPOLL_CTL_ADD, wayland_fd, &ev) ==
      -1) {
    FATAL("epoll_ctl: wayland_fd");
  }

  INFO("client initialized", "");
  return wayland_fd;
}

void make_wayland_connection(int instance_no, int peer_fd) {

  int i;

  for (i = 0; i < MAX_CLIENTS; i++) {
    if (fd_map[instance_no][i].my_fd == -1) {
      fd_map[instance_no][i].my_fd = wayland_connect(instance_no);
      fd_map[instance_no][i].remote_fd = peer_fd;
      return;
    }
  }
  ERROR("FAILED fd#%d", peer_fd);
  FATAL("fd_map table full");
}

int map_peer_fd(int instance_no, int peer_fd, int close_fd) {

  int i, rv;

  for (i = 0; i < MAX_CLIENTS; i++) {
    if (fd_map[instance_no][i].remote_fd == peer_fd) {
      rv = fd_map[instance_no][i].my_fd;
      if (close_fd)
        fd_map[instance_no][i].my_fd = -1;
      return rv;
    }
  }
  ERROR("FAILED on mapping remote fd#%d", peer_fd);
  return -1;
}

int get_remote_socket(int instance_no, int my_fd, int close_fd,
                      int ignore_error) {

  int i;

  for (i = 0; i < MAX_CLIENTS; i++) {
    if (fd_map[instance_no][i].my_fd == my_fd) {
      if (close_fd)
        fd_map[instance_no][i].my_fd = -1;
      return fd_map[instance_no][i].remote_fd;
    }
  }
  if (ignore_error)
    return -1;

  FATAL("my fd not found");
  return -1;
}

void shmem_init(int instance_no) {

  int res = -1, vm_id;
  struct epoll_event ev;
  long int shmem_size;

  /* Open shared memory */
  shmem_fd[instance_no] = open(SHM_DEVICE_FN, O_RDWR);
  if (shmem_fd[instance_no] < 0) {
    FATAL("Open " SHM_DEVICE_FN);
  }
  INFO("shared memory fd: %d", shmem_fd[instance_no]);
  /* Store instance number inside driver */
  ioctl(shmem_fd[instance_no], SHMEM_IOCSETINSTANCENO, instance_no);

  /* Get shared memory */
  shmem_size = get_shmem_size(instance_no);
  if (shmem_size <= 0) {
    FATAL("No shared memory detected");
  }
  if (shmem_size < sizeof(*vm_control)) {
    ERROR("Shared memory too small: %ld bytes allocated whereas %ld needed",
          shmem_size, sizeof(*vm_control));
    FATAL("Exiting");
  }
  vm_control = mmap(NULL, shmem_size, PROT_READ | PROT_WRITE,
                    MAP_SHARED | MAP_NORESERVE, shmem_fd[instance_no], 0);
  if (!vm_control) {
    FATAL("Got NULL pointer from mmap");
  }
  DEBUG("Shared memory at address %p 0x%lx bytes", vm_control, shmem_size);

  if (run_as_server) {
    my_shm_data[instance_no] = &vm_control->server_data[instance_no];
    peer_shm_data[instance_no] = &vm_control->client_data[instance_no];
  } else {
    my_shm_data[instance_no] = &vm_control->client_data[instance_no];
    peer_shm_data[instance_no] = &vm_control->server_data[instance_no];
  }

  /* get my VM Id */
  res = ioctl(shmem_fd[instance_no], SHMEM_IOCIVPOSN, &vm_id);
  if (res < 0) {
    FATAL("ioctl SHMEM_IOCIVPOSN failed");
  }
  vm_id = vm_id << 16;
  if (run_as_server) {
    my_vmid = &vm_control->server_data[instance_no].server_vmid;
  } else {
    my_vmid = &vm_control->client_vmid;
    vm_control->server_data[instance_no].server_vmid = UNKNOWN_PEER;
  }
  *my_vmid = vm_id;
  INFO("My VM id = 0x%x. Running as a ", *my_vmid);
  if (run_as_server) {
    INFO("server", "");
  } else {
    INFO("client", "");
  }

  ev.events = EPOLLIN | EPOLLOUT;
  ev.data.fd = shmem_fd[instance_no];
  if (epoll_ctl(epollfd_full[instance_no], EPOLL_CTL_ADD, shmem_fd[instance_no],
                &ev) == -1) {
    FATAL("epoll_ctl: -1");
  }
  ev.events = EPOLLIN | EPOLLOUT;
  ev.data.fd = shmem_fd[instance_no];
  if (epoll_ctl(epollfd_limited[instance_no], EPOLL_CTL_ADD,
                shmem_fd[instance_no], &ev) == -1) {
    FATAL("epoll_ctl: -1");
  }
  /* Set output buffer it's available */
  ioctl(shmem_fd[instance_no], SHMEM_IOCSET,
        (LOCAL_RESOURCE_READY_INT_VEC << 8) + 1);

  INFO("shared memory initialized", "");
}

void thread_init(int instance_no) {

  int res;
  struct ioctl_data ioctl_data;

  fd_map_clear(instance_no);

  epollfd_full[instance_no] = epoll_create1(0);
  if (epollfd_full[instance_no] == -1) {
    FATAL("server_init: epoll_create1");
  }
  epollfd_limited[instance_no] = epoll_create1(0);
  if (epollfd_limited[instance_no] == -1) {
    FATAL("server_init: epoll_create1");
  }

  shmem_init(instance_no);

  if (run_as_server) {
    /* Create socket that waypipe can write to
     * Add the socket fd to the epollfd_full
     */
    server_init(instance_no);
    local_rr_int_no[instance_no] = vm_control->client_vmid |
                                   (instance_no << 1) |
                                   LOCAL_RESOURCE_READY_INT_VEC;
    remote_rc_int_no[instance_no] = vm_control->client_vmid |
                                    (instance_no << 1) |
                                    PEER_RESOURCE_CONSUMED_INT_VEC;
    /*
     * Send LOGIN cmd to the client. Supply my_vmid
     */
    my_shm_data[instance_no]->cmd = CMD_LOGIN;
    my_shm_data[instance_no]->fd = *my_vmid;
    my_shm_data[instance_no]->len = 0;

    ioctl_data.int_no = local_rr_int_no[instance_no];

#ifdef DEBUG_IOCTL
    ioctl_data.cmd = my_shm_data[instance_no]->cmd;
    ioctl_data.fd = my_shm_data[instance_no]->fd;
    ioctl_data.len = my_shm_data[instance_no]->len;
#endif

    res = ioctl(shmem_fd[instance_no], SHMEM_IOCDORBELL, &ioctl_data);
    DEBUG("Client #%d: sent login vmid: 0x%x ioctl result=%d client vm_id=0x%x",
          instance_no, *my_vmid, res, vm_control->client_vmid);
  }
}

void close_peer_vm(int instance_no) {
  int i;

  for (i = 0; i < MAX_CLIENTS; i++) {
    if (fd_map[instance_no][i].my_fd != -1)
      close(fd_map[instance_no][i].my_fd);
  }
  fd_map_clear(instance_no);
}

int wait_shmem_ready(int instance_no, struct pollfd *my_buffer_fds) {
  int rv;

  rv = poll(my_buffer_fds, 1, SHMEM_POLL_TIMEOUT);
  if (rv < 0) {
    ERROR("poll failed fd=%d poll=%d", my_buffer_fds->fd, rv);
    return -1;
  }

  if (rv == 0 || (my_buffer_fds->revents & ~POLLOUT)) {
    ERROR("unexpected event or timeout on shmem_fd %d: poll=%d fd=%d "
          "revents=0x%x "
          "events=0x%x",
          shmem_fd[instance_no], rv, my_buffer_fds->fd, my_buffer_fds->revents,
          my_buffer_fds->events);
    return 0;
  }

  return rv;
}

int cksum(unsigned char *buf, int len) {
  int i, res = 0;
  for (i = 0; i < len; i++)
    res += buf[i];
  return res;
}

void *run(void *arg) {

  int instance_no = (intptr_t)arg;
  int conn_fd, rv, nfds, n, read_count;
  struct sockaddr_un caddr;      /* client address */
  socklen_t len = sizeof(caddr); /* address length could change */
  struct pollfd my_buffer_fds = {.events = POLLOUT};
  struct epoll_event ev, *current_event;
  struct epoll_event events[MAX_EVENTS];
  struct ioctl_data ioctl_data;
  unsigned int tmp, data_chunk;
  int epollfd;
  vm_data *peer_shm, *my_shm;
  
  thread_init(instance_no);
  peer_shm = peer_shm_data[instance_no];
  my_shm = my_shm_data[instance_no];
  my_buffer_fds.fd = shmem_fd[instance_no];
  epollfd = epollfd_full[instance_no];

  while (1) {
#ifdef DEBUG_ON
    if (epollfd == epollfd_full[instance_no]) {
      DEBUG("Waiting for all events", "");
    } else {
      DEBUG("Waiting for ACK", "");
    }
#endif
    nfds = epoll_wait(epollfd, events, MAX_EVENTS, -1);
    if (nfds == -1) {
      FATAL("epoll_wait");
    }

    for (n = 0; n < nfds; n++) {
      current_event = &events[n];
#ifdef DEBUG_ON
      ioctl(my_buffer_fds.fd, SHMEM_IOCNOP, &tmp);
      DBG("Event index=%d 0x%x on fd %d inout=%d-%d", n, current_event->events,
          current_event->data.fd, tmp & 0xffff, tmp >> 16);
#endif
      if (current_event->events & EPOLLOUT &&
          current_event->data.fd == my_buffer_fds.fd) {
        DEBUG("Remote ACK", "");
        /* Set the local buffer is consumed and ready for use */
        ioctl(my_buffer_fds.fd, SHMEM_IOCSET,
              (LOCAL_RESOURCE_READY_INT_VEC << 8) + 0);
        epollfd = epollfd_full[instance_no];
      }

      /* Handle the new connection on the socket */
      if (current_event->events & EPOLLIN) {
        if (run_as_server && current_event->data.fd == server_socket) {
          conn_fd = accept(server_socket, (struct sockaddr *)&caddr, &len);
          if (conn_fd == -1) {
            FATAL("accept");
          }
          ev.events = EPOLLIN | EPOLLET | EPOLLHUP;
          ev.data.fd = conn_fd;
          if (epoll_ctl(epollfd_full[instance_no], EPOLL_CTL_ADD, conn_fd,
                        &ev) == -1) {
            FATAL("epoll_ctl: conn_fd");
          }
          /* Send the connect request to the wayland peer */
          my_shm->cmd = CMD_CONNECT;
          my_shm->fd = conn_fd;
          my_shm->len = 0;
          ioctl_data.int_no = local_rr_int_no[instance_no];
#ifdef DEBUG_IOCTL
          ioctl_data.cmd = my_shm->cmd;
          ioctl_data.fd = my_shm->fd;
          ioctl_data.len = my_shm->len;
#endif
          epollfd = epollfd_limited[instance_no];
          ioctl(my_buffer_fds.fd, SHMEM_IOCDORBELL, &ioctl_data);
          DEBUG("Executed ioctl to add the client on fd %d", conn_fd);
        }

        /* Both sides: Received data from the peer via shared memory - EPOLLIN
         */
        else if (current_event->data.fd == my_buffer_fds.fd) {
          DEBUG(
              "shmem_fd=%d event: 0x%x cmd: 0x%x remote fd: %d remote len: %d",
              my_buffer_fds.fd, current_event->events,
              peer_shm->cmd, peer_shm->fd,
              peer_shm->len);

          switch (peer_shm->cmd) {
          case CMD_LOGIN:
            DEBUG("Received login request from 0x%x",
                  peer_shm->fd);
            /* If the peer VM starts again, close all opened file handles */
            close_peer_vm(instance_no);

            local_rr_int_no[instance_no] = peer_shm->fd |
                                           (instance_no << 1) |
                                           LOCAL_RESOURCE_READY_INT_VEC;
            remote_rc_int_no[instance_no] = peer_shm->fd |
                                            (instance_no << 1) |
                                            PEER_RESOURCE_CONSUMED_INT_VEC;

            peer_shm->fd = -1;
            break;
          case CMD_DATA:
          case CMD_DATA_CLOSE:
            conn_fd = run_as_server
                          ? peer_shm->fd
                          : map_peer_fd(instance_no,
                                        peer_shm->fd, 0);
            DEBUG("shmem: received %d bytes for %d cksum=0x%x",
                  peer_shm->len, conn_fd,
                  cksum((unsigned char *)peer_shm->data,
                        peer_shm->len));
            for (tmp = 0; tmp < peer_shm->len; tmp += PAGE_SIZE) {

              data_chunk = ((peer_shm->len - tmp) / PAGE_SIZE) ? PAGE_SIZE:peer_shm->len - tmp;

              rv = send(conn_fd, (void *)&peer_shm->data[tmp],
                        data_chunk, 0);
              if (rv != data_chunk) {
                ERROR("Sent %d out of %d bytes on fd#%d", rv,
                      data_chunk, conn_fd);
              }
            }
            DEBUG("Received data has been sent", "");

            if (peer_shm->cmd == CMD_DATA) {
              break;
            }
            /* no break if we need to the the fd */
          case CMD_CLOSE:
            if (run_as_server) {
              conn_fd = peer_shm->fd;
              DEBUG("Closing %d", conn_fd);
            } else {
              conn_fd =
                  map_peer_fd(instance_no, peer_shm->fd, 1);
              DEBUG("Closing %d peer fd=%d", conn_fd,
                    peer_shm->fd);
            }
            if (conn_fd > 0) {
              if (epoll_ctl(epollfd_full[instance_no], EPOLL_CTL_DEL, conn_fd,
                            NULL) == -1) {
                ERROR0("epoll_ctl: EPOLL_CTL_DEL");
              }
              close(conn_fd);
            }
            break;
          case CMD_CONNECT:
            make_wayland_connection(instance_no,
                                    peer_shm->fd);
            break;
          default:
            ERROR("Invalid CMD 0x%x from peer!",
                  peer_shm->cmd);
            break;
          } /* switch peer_shm->cmd */

          /* Signal the other side that its buffer has been processed */
          DEBUG("Exec ioctl REMOTE_RESOURCE_CONSUMED_INT_VEC", "");
          peer_shm->cmd = -1;

          ioctl_data.int_no = remote_rc_int_no[instance_no];
#ifdef DEBUG_IOCTL
          ioctl_data.cmd = -1;
          ioctl_data.fd = 0;
          ioctl_data.len = 0;
#endif
          ioctl(my_buffer_fds.fd, SHMEM_IOCDORBELL, &ioctl_data);
        } /* End of "data arrived from the peer via shared memory" */

        /* Received data from Wayland or from waypipe. It needs to
          be sent to the peer */
        else {
          if (!run_as_server) {
            conn_fd = get_remote_socket(instance_no, current_event->data.fd, 0,
                                        IGNORE_ERROR);
            DEBUG("get_remote_socket: %d", conn_fd);
          } else {
            conn_fd = current_event->data.fd;
          }
          DEBUG("Reading from wayland/waypipe socket", "");
          read_count =
              read(current_event->data.fd, (void *)my_shm->data,
                   sizeof(my_shm->data));

          if (read_count <= 0) {
            if (read_count < 0)
              ERROR("read from wayland/waypipe socket failed fd=%d",
                    current_event->data.fd);
            /* Release output buffer */
            ioctl(my_buffer_fds.fd, SHMEM_IOCSET,
                  (LOCAL_RESOURCE_READY_INT_VEC << 8) + 1);

          } else { /* read_count > 0 */
            DEBUG("Read & sent %d bytes on fd#%d sent to %d checksum=0x%x",
                  read_count, current_event->data.fd, conn_fd,
                  cksum((unsigned char *)my_shm->data,
                        read_count));

            if (current_event->events & EPOLLHUP) {
              my_shm->cmd = CMD_DATA_CLOSE;
              current_event->events &= ~EPOLLHUP;

              /* unmap local fd */
              if (!run_as_server)
                get_remote_socket(instance_no, current_event->data.fd, CLOSE_FD,
                                  IGNORE_ERROR);
              /* close local fd*/
              close(current_event->data.fd);
            } else
              my_shm->cmd = CMD_DATA;

            my_shm->fd = conn_fd;
            my_shm->len = read_count;

            ioctl_data.int_no = local_rr_int_no[instance_no];
#ifdef DEBUG_IOCTL
            ioctl_data.cmd = my_shm->cmd;
            ioctl_data.fd = my_shm->fd;
            ioctl_data.len = my_shm->len;
#endif
            DEBUG("Exec ioctl DATA/DATA_CLOSE cmd=%d fd=%d len=%d",
                  my_shm->cmd, my_shm->fd,
                  my_shm->len);
            epollfd = epollfd_limited[instance_no];
            ioctl(my_buffer_fds.fd, SHMEM_IOCDORBELL, &ioctl_data);
            break;
          }
        } /* received data from Wayland/waypipe server */
      }   /* current_event->events & EPOLLIN */

      /* Handling connection close */
      if (current_event->events & (EPOLLHUP | EPOLLERR)) {
        DEBUG("Closing fd#%d", current_event->data.fd);
        my_shm->cmd = CMD_CLOSE;
        if (run_as_server)
          my_shm->fd = current_event->data.fd;
        else {
          DEBUG("get_remote_socket: %d",
                get_remote_socket(instance_no, current_event->data.fd, 0,
                                  IGNORE_ERROR));
          my_shm->fd = get_remote_socket(
              instance_no, current_event->data.fd, CLOSE_FD, IGNORE_ERROR);
        }
        if (my_shm->fd > 0) {
          DEBUG("ioctl ending close request for %d",
                my_shm->fd);

          ioctl_data.int_no = local_rr_int_no[instance_no];
#ifdef DEBUG_IOCTL
          ioctl_data.cmd = my_shm->cmd;
          ioctl_data.fd = my_shm->fd;
          ioctl_data.len = my_shm->len;
#endif
          /* Output buffer is busy. Accept only the interrupts
             that don't use it */
          epollfd = epollfd_limited[instance_no];
          ioctl(my_buffer_fds.fd, SHMEM_IOCDORBELL, &ioctl_data);

        } else { /* unlock output buffer */
          ERROR("Attempt to close invalid fd %d", current_event->data.fd);
          ioctl(my_buffer_fds.fd, SHMEM_IOCSET,
                (LOCAL_RESOURCE_READY_INT_VEC << 8) + 1);
        }
        if (epoll_ctl(epollfd_full[instance_no], EPOLL_CTL_DEL,
                      current_event->data.fd, NULL) == -1) {
          ERROR("epoll_ctl: EPOLL_CTL_DEL on fd %d", current_event->data.fd);
        }
        close(current_event->data.fd);
        /* If the buffer is busy, don't proceed any further events */
        if (epollfd == epollfd_limited[instance_no])
          break;
      } /* Handling connection close */
    }
  } /* while(1) */
  return 0;
}

void print_usage_and_exit() {
  fprintf(stderr, usage_string);
  exit(1);
}

int main(int argc, char **argv) {

  int i, res = -1;
  int instance_no = 0;
  pthread_t threads[VM_COUNT];

  if (argc <= 2)
    goto wrong_args;
  if (strcmp(argv[1], "-c") == 0) {
    run_as_server = 0;
  } else if (strcmp(argv[1], "-s") == 0) {
    run_as_server = 1;
  } else
    goto wrong_args;

  if ((run_as_server && argc != 4) || (!run_as_server && argc != 3))
    goto wrong_args;

  socket_path = argv[2];
  if (!strlen(socket_path))
    goto wrong_args;

  if (run_as_server) {
    if (strlen(argv[3])) {
      instance_no = atoi(argv[3]);
    } else {
      goto wrong_args;
    }
  }
  for (i = 0; i < VM_COUNT; i++) {
    my_shm_data[i] = NULL;
    peer_shm_data[i] = NULL;
    shmem_fd[i] = -1;
  }

  /* On client site start thread for each display VM */
  if (run_as_server == 0) {
    for (i = 0; i < VM_COUNT; i++) {
      res = pthread_create(&threads[i], NULL, run, (void *)(intptr_t)i);
      if (res) {
        ERROR("Thread id=%d", i);
        FATAL("Cannot create a thread");
      }
    }

    for (i = 0; i < VM_COUNT; i++) {
      res = pthread_join(threads[i], NULL);
      if (res) {
        ERROR("error %d waiting for the thread #%d", res, i);
      }
    }
  } else { /* server mode - run only one instance */
    run((void *)(intptr_t)instance_no);
  }

  return 0;
wrong_args:
  print_usage_and_exit();
  return 1;
}
