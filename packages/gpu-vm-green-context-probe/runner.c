// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
//
// Verify that the passed-through GPU supports two CUDA Green Context resource
// groups. This diagnostic deliberately launches no workload kernels.
#include <cuda.h>

#include <errno.h>
#include <getopt.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct green_partition {
  CUdevice device;
  CUcontext primary;
  bool primary_retained;
  CUdevResource groups[2];
  CUdevResource remainder;
  CUdevResourceDesc descriptors[2];
  CUgreenCtx contexts[2];
  unsigned int group_count;
};

static void cuda_result(const char *call, CUresult result) {
  const char *name = "unknown";
  const char *description = "unknown";

  (void)cuGetErrorName(result, &name);
  (void)cuGetErrorString(result, &description);
  printf("CUDA call=%s result=%d name=%s description=%s\n", call,
         (int)result, name != NULL ? name : "unknown",
         description != NULL ? description : "unknown");
}

#define PROBE_CALL(expression)                                                 \
  do {                                                                         \
    CUresult call_result = (expression);                                       \
    cuda_result(#expression, call_result);                                     \
    if (call_result == CUDA_ERROR_NOT_SUPPORTED) {                             \
      fprintf(stderr,                                                          \
              "GREEN_CONTEXT_UNSUPPORTED reason=cuda_api call=%s\n",         \
              #expression);                                                    \
      goto fail;                                                               \
    }                                                                          \
    if (call_result != CUDA_SUCCESS) {                                         \
      fprintf(stderr, "GREEN_CONTEXT_FAIL reason=cuda_api call=%s\n",        \
              #expression);                                                    \
      goto fail;                                                               \
    }                                                                          \
  } while (0)

static bool parse_unsigned(const char *text, unsigned int minimum,
                           unsigned int maximum, unsigned int *value) {
  char *end = NULL;
  unsigned long parsed;

  errno = 0;
  parsed = strtoul(text, &end, 10);
  if (errno != 0 || text[0] == '\0' || end == NULL || *end != '\0' ||
      parsed < minimum || parsed > maximum)
    return false;
  *value = (unsigned int)parsed;
  return true;
}

static void usage(FILE *stream, const char *program) {
  fprintf(stream, "Usage: %s [--min-sm-count N]\n", program);
}

static bool parse_options(int argc, char **argv,
                          unsigned int *min_sm_count) {
  static const struct option long_options[] = {
      {"min-sm-count", required_argument, NULL, 'm'},
      {"help", no_argument, NULL, 'h'},
      {NULL, 0, NULL, 0},
  };
  int option;

  *min_sm_count = 4;
  while ((option = getopt_long(argc, argv, "m:h", long_options, NULL)) != -1) {
    switch (option) {
    case 'm':
      if (!parse_unsigned(optarg, 1, 1024, min_sm_count))
        return false;
      break;
    case 'h':
      usage(stdout, argv[0]);
      exit(EXIT_SUCCESS);
    default:
      return false;
    }
  }
  return optind == argc;
}

static void destroy_partition(struct green_partition *partition) {
  for (int index = 1; index >= 0; index--) {
    if (partition->contexts[index] != NULL) {
      CUresult result = cuGreenCtxDestroy(partition->contexts[index]);
      cuda_result("cuGreenCtxDestroy", result);
      partition->contexts[index] = NULL;
    }
  }
  if (partition->primary_retained) {
    CUresult result = cuDevicePrimaryCtxRelease(partition->device);
    cuda_result("cuDevicePrimaryCtxRelease", result);
    partition->primary_retained = false;
  }
}

static bool create_partition(struct green_partition *partition,
                             unsigned int min_sm_count) {
  CUdevResource device_resource = {0};
  CUdevResource queried = {0};
  unsigned int dry_run_groups = 2;
  int driver_version = 0;
  int device_count = 0;
  int major = 0;
  int minor = 0;
  char device_name[256] = {0};

  memset(partition, 0, sizeof(*partition));

  PROBE_CALL(cuInit(0));
  PROBE_CALL(cuDriverGetVersion(&driver_version));
  PROBE_CALL(cuDeviceGetCount(&device_count));
  if (device_count < 1) {
    fprintf(stderr, "GREEN_CONTEXT_UNSUPPORTED reason=no_cuda_device\n");
    goto fail;
  }
  PROBE_CALL(cuDeviceGet(&partition->device, 0));
  PROBE_CALL(cuDeviceGetName(device_name, sizeof(device_name),
                             partition->device));
  PROBE_CALL(cuDeviceGetAttribute(
      &major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, partition->device));
  PROBE_CALL(cuDeviceGetAttribute(
      &minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, partition->device));
  printf("device=0 name=%s driver_version=%d compute_capability=sm_%d%d\n",
         device_name, driver_version, major, minor);

  PROBE_CALL(cuDevicePrimaryCtxRetain(&partition->primary,
                                      partition->device));
  partition->primary_retained = true;
  PROBE_CALL(cuCtxSetCurrent(partition->primary));
  PROBE_CALL(cuDeviceGetDevResource(partition->device, &device_resource,
                                    CU_DEV_RESOURCE_TYPE_SM));
  printf("device_sm_count=%u requested_groups=2 min_sm_count=%u\n",
         device_resource.sm.smCount, min_sm_count);

  PROBE_CALL(cuDevSmResourceSplitByCount(
      NULL, &dry_run_groups, &device_resource, NULL, 0, min_sm_count));
  printf("dry_run_group_count=%u\n", dry_run_groups);
  if (dry_run_groups < 2) {
    fprintf(stderr,
            "GREEN_CONTEXT_UNSUPPORTED reason=insufficient_symmetric_groups "
            "groups=%u\n",
            dry_run_groups);
    goto fail;
  }

  partition->group_count = 2;
  PROBE_CALL(cuDevSmResourceSplitByCount(
      partition->groups, &partition->group_count, &device_resource,
      &partition->remainder, 0, min_sm_count));
  if (partition->group_count != 2) {
    fprintf(stderr,
            "GREEN_CONTEXT_UNSUPPORTED reason=real_split_group_count "
            "groups=%u\n",
            partition->group_count);
    goto fail;
  }
  printf("split group0_sm_count=%u group1_sm_count=%u remainder_sm_count=%u\n",
         partition->groups[0].sm.smCount, partition->groups[1].sm.smCount,
         partition->remainder.type == CU_DEV_RESOURCE_TYPE_SM
             ? partition->remainder.sm.smCount
             : 0);

  for (unsigned int index = 0; index < partition->group_count; index++) {
    PROBE_CALL(cuDevResourceGenerateDesc(&partition->descriptors[index],
                                         &partition->groups[index], 1));
    PROBE_CALL(cuGreenCtxCreate(&partition->contexts[index],
                                partition->descriptors[index],
                                partition->device,
                                CU_GREEN_CTX_DEFAULT_STREAM));
    PROBE_CALL(cuGreenCtxGetDevResource(partition->contexts[index], &queried,
                                        CU_DEV_RESOURCE_TYPE_SM));
    printf("green_context=%u requested_sm_count=%u queried_sm_count=%u\n",
           index, partition->groups[index].sm.smCount, queried.sm.smCount);
    if (queried.type != CU_DEV_RESOURCE_TYPE_SM ||
        queried.sm.smCount != partition->groups[index].sm.smCount) {
      fprintf(stderr,
              "GREEN_CONTEXT_FAIL reason=resource_query_mismatch context=%u\n",
              index);
      goto fail;
    }
  }

  PROBE_CALL(cuCtxSetCurrent(NULL));
  printf("GREEN_CONTEXT_PROBE_OK groups=2\n");
  return true;

fail:
  (void)cuCtxSetCurrent(NULL);
  destroy_partition(partition);
  return false;
}

int main(int argc, char **argv) {
  struct green_partition partition;
  unsigned int min_sm_count;

  setvbuf(stdout, NULL, _IOLBF, 0);
  if (!parse_options(argc, argv, &min_sm_count)) {
    usage(stderr, argv[0]);
    return 2;
  }
  if (!create_partition(&partition, min_sm_count))
    return 1;
  destroy_partition(&partition);
  return 0;
}
