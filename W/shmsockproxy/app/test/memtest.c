#include <ctype.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <time.h>
#include <sys/times.h>

#define LISTEN_BACKLOG 50
#define BUFFER_SIZE (10240)
#define handle_error(msg)                                                      \
  do {                                                                         \
    perror(msg);                                                               \
    exit(EXIT_FAILURE);                                                        \
  } while (0)
#define CRC8_RESIDUE (0xea)

static unsigned char const crc8_table[] = {
    0xea, 0xd4, 0x96, 0xa8, 0x12, 0x2c, 0x6e, 0x50, 0x7f, 0x41, 0x03, 0x3d,
    0x87, 0xb9, 0xfb, 0xc5, 0xa5, 0x9b, 0xd9, 0xe7, 0x5d, 0x63, 0x21, 0x1f,
    0x30, 0x0e, 0x4c, 0x72, 0xc8, 0xf6, 0xb4, 0x8a, 0x74, 0x4a, 0x08, 0x36,
    0x8c, 0xb2, 0xf0, 0xce, 0xe1, 0xdf, 0x9d, 0xa3, 0x19, 0x27, 0x65, 0x5b,
    0x3b, 0x05, 0x47, 0x79, 0xc3, 0xfd, 0xbf, 0x81, 0xae, 0x90, 0xd2, 0xec,
    0x56, 0x68, 0x2a, 0x14, 0xb3, 0x8d, 0xcf, 0xf1, 0x4b, 0x75, 0x37, 0x09,
    0x26, 0x18, 0x5a, 0x64, 0xde, 0xe0, 0xa2, 0x9c, 0xfc, 0xc2, 0x80, 0xbe,
    0x04, 0x3a, 0x78, 0x46, 0x69, 0x57, 0x15, 0x2b, 0x91, 0xaf, 0xed, 0xd3,
    0x2d, 0x13, 0x51, 0x6f, 0xd5, 0xeb, 0xa9, 0x97, 0xb8, 0x86, 0xc4, 0xfa,
    0x40, 0x7e, 0x3c, 0x02, 0x62, 0x5c, 0x1e, 0x20, 0x9a, 0xa4, 0xe6, 0xd8,
    0xf7, 0xc9, 0x8b, 0xb5, 0x0f, 0x31, 0x73, 0x4d, 0x58, 0x66, 0x24, 0x1a,
    0xa0, 0x9e, 0xdc, 0xe2, 0xcd, 0xf3, 0xb1, 0x8f, 0x35, 0x0b, 0x49, 0x77,
    0x17, 0x29, 0x6b, 0x55, 0xef, 0xd1, 0x93, 0xad, 0x82, 0xbc, 0xfe, 0xc0,
    0x7a, 0x44, 0x06, 0x38, 0xc6, 0xf8, 0xba, 0x84, 0x3e, 0x00, 0x42, 0x7c,
    0x53, 0x6d, 0x2f, 0x11, 0xab, 0x95, 0xd7, 0xe9, 0x89, 0xb7, 0xf5, 0xcb,
    0x71, 0x4f, 0x0d, 0x33, 0x1c, 0x22, 0x60, 0x5e, 0xe4, 0xda, 0x98, 0xa6,
    0x01, 0x3f, 0x7d, 0x43, 0xf9, 0xc7, 0x85, 0xbb, 0x94, 0xaa, 0xe8, 0xd6,
    0x6c, 0x52, 0x10, 0x2e, 0x4e, 0x70, 0x32, 0x0c, 0xb6, 0x88, 0xca, 0xf4,
    0xdb, 0xe5, 0xa7, 0x99, 0x23, 0x1d, 0x5f, 0x61, 0x9f, 0xa1, 0xe3, 0xdd,
    0x67, 0x59, 0x1b, 0x25, 0x0a, 0x34, 0x76, 0x48, 0xf2, 0xcc, 0x8e, 0xb0,
    0xd0, 0xee, 0xac, 0x92, 0x28, 0x16, 0x54, 0x6a, 0x45, 0x7b, 0x39, 0x07,
    0xbd, 0x83, 0xc1, 0xff};

unsigned crc8(unsigned crc, unsigned char const *data, size_t len) {
  if (data == NULL)
    return 0;
  crc &= 0xff;
  unsigned char const *end = data + len;
  while (data < end)
    crc = crc8_table[crc ^ *data++];
  return crc;
}

void time_report(struct tms *start, struct tms *end, clock_t c_start, clock_t c_end, long int sent_bytes)
{
    double time_elapsed = c_end - c_start;
    double real_time = (double)(c_end - c_start) / sysconf(_SC_CLK_TCK);
    double bytes_per_sec = (double) sent_bytes  / real_time;
    double u_time = (double)(end->tms_utime - start->tms_utime) / sysconf(_SC_CLK_TCK);
    double s_time = (double)(end->tms_stime - start->tms_stime) / sysconf(_SC_CLK_TCK);
    
    printf("Sent/received %ld bytes %.0f Mbytes/sec\n", sent_bytes, bytes_per_sec/1024/1024);
    printf("real %.3fs\nuser %.3fs\nsys  %.3fs\n", real_time, u_time, s_time);
}

void receive_file(char *socket_path) {

  int sfd, cfd;
  socklen_t peer_addr_size;
  struct sockaddr_un my_addr, peer_addr;
  unsigned char buff[BUFFER_SIZE];
  int res, rv, read_count;
  unsigned int crc;
  struct tms time_start, time_end;
  clock_t r_time_start, r_time_end;

  sfd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sfd == -1)
    handle_error("socket");

  memset(&my_addr, 0, sizeof(my_addr));
  my_addr.sun_family = AF_UNIX;
  strncpy(my_addr.sun_path, socket_path, sizeof(my_addr.sun_path) - 1);

  unlink(socket_path);
  if (bind(sfd, (struct sockaddr *)&my_addr, sizeof(my_addr)) == -1)
    handle_error("bind");
  printf("Waiting for a connection.\n");
  while (1) {
    if (listen(sfd, LISTEN_BACKLOG) == -1)
      handle_error("listen");

    /* Now we can accept incoming connections one
        at a time using accept(2). */

    peer_addr_size = sizeof(peer_addr);
    cfd = accept(sfd, (struct sockaddr *)&peer_addr, &peer_addr_size);

    if (cfd == -1)
      handle_error("accept");
    printf("Connected...\n");
    read_count = 0;
    crc = 0;
    r_time_start = times(&time_start);
    while (1) {
      rv = read(cfd, buff, sizeof(buff));
      if (rv < 0)
        handle_error("read");
      if (rv == 0)
        break;
      read_count += rv;
      crc = crc8(crc, buff, rv);
    };
    r_time_end = times(&time_end);
    time_report(&time_start, &time_end, r_time_start, r_time_end, read_count+1);
    printf("Read %d bytes.", read_count);
    if (crc == CRC8_RESIDUE) 
      printf(" CRC OK\n");
    else
      printf(" BAD CRC!\n");
    if (close(cfd) == -1)
      handle_error("close");
  }
}

void send_file(char *socket_path, char *input_file, int size, int error) {
  int in_fd, out_fd;
  struct sockaddr_un socket_name;
  long int sent_bytes = 0, rv, wv;
  unsigned char buff[BUFFER_SIZE];
  unsigned crc;
  struct tms time_start, time_end;
  clock_t r_time_start, r_time_end;

  out_fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (out_fd < 0) {
    handle_error("socket");
  }

  memset(&socket_name, 0, sizeof(socket_name));
  socket_name.sun_family = AF_UNIX;
  strncpy(socket_name.sun_path, socket_path, sizeof(socket_name.sun_path) - 1);
  if (connect(out_fd, (struct sockaddr *)&socket_name, sizeof(socket_name)) <
      0) {
    handle_error("connect");
  }

  in_fd = open(input_file, O_RDONLY);
  if (in_fd <= 0) {
    handle_error("open in");
  }

  crc = 0;
  r_time_start = times(&time_start);
  while(1) {
    rv = read(in_fd, buff, sizeof(buff));
    if (rv < 0)
      handle_error("read");
    if (!rv)
      break;
    wv = write(out_fd, buff, rv);
    if (wv <= 0)
      handle_error("write");

    crc = crc8(crc, buff, rv);
    sent_bytes += rv;
    if(size && sent_bytes >=size)
      break;
  };
  buff[0] = crc & 0xff;
  if (error) 
    buff[0]--;
  wv = write(out_fd, buff, 1);

  r_time_end = times(&time_end);
  time_report(&time_start, &time_end, r_time_start, r_time_end, sent_bytes+1);
  if (wv <= 0)
    handle_error("write");
}

void usage(char *cmd) {
  printf("Usage: %s socket_path for receiving.\n%s socket_path input_file [size CRC_error]"
         " for sending.\nBefore using stop the memsocket service: 'systemctl stop --user memsocket.service'.\n"
         "For receiving run e.g.: 'memsocket -c ./test.sock &; %s ./test.sock'.\n"
         "To send a file run on other VM: 'memsocket -s ./test.sock 3 &; %s ./test.sock /dev/random 10M.'\n"
         "To force wrong CRC on sending: '%s ./test.sock /dev/random 10M xxx\n'"
         ,
         cmd, cmd, cmd, cmd, cmd);
  exit(0);
}

int main(int argc, char **argv) {

  long int size = 0;
  int m = 1;
  char c;
  char socket_path[100], file_path[100];

  if (argc < 2) {
    usage(argv[0]);
  }
  strcpy(socket_path, argv[1]);
  if (argc == 2) {
    receive_file(socket_path);
  } else {
    strcpy(file_path, argv[2]);
    if (argc >= 4) {
      c = toupper(argv[3][strlen(argv[3]) - 1]);
      if (c == 'K')
        m = 1024;
      else if (c == 'M')
        m = 1024 * 1024;
      else if (c == 'G')
        m = 1024 * 1024 * 1024;
      size = m * atoi(argv[3]);
      // printf("size=%ld\n", size);
    }

    // printf(">>%d\n", __LINE__);
    send_file(socket_path, file_path, size, argc ==5 );
  }
}
