/* Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
   SPDX-License-Identifier: Apache-2.0
*/

#define PEER_RESOURCE_CONSUMED_INT_VEC (0)
#define LOCAL_RESOURCE_READY_INT_VEC (1)

#define SHMEM_IOC_MAGIC 's'

#define SHMEM_IOCWLOCAL _IOR(SHMEM_IOC_MAGIC, 1, int)
#define SHMEM_IOCWPEER _IOR(SHMEM_IOC_MAGIC, 2, int)
#define SHMEM_IOCIVPOSN _IOW(SHMEM_IOC_MAGIC, 3, int)
#define SHMEM_IOCSETINSTANCENO _IOR(SHMEM_IOC_MAGIC, 4, int)
#define SHMEM_IOCSET _IOR(SHMEM_IOC_MAGIC, 5, int)
#define SHMEM_IOCDORBELL _IOR(SHMEM_IOC_MAGIC, 6, int)
#define SHMEM_IOCNOP _IOR(SHMEM_IOC_MAGIC, 7, int)

// #define DEBUG_IOCTL
struct ioctl_data {
  int peer_vm_id;
  unsigned int int_no;
  int fd;
  int cmd;
  int len;
};
