/*
 * SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
 *
 * egl-device-shim: fake EGL_EXT_device enumeration for the L4T/Tegra NVIDIA EGL.
 *
 * cosmic-comp (smithay's udev backend) associates each DRM device with an EGL
 * device: it calls eglQueryDevicesEXT() and, for each returned EGLDeviceEXT,
 * eglQueryDeviceStringEXT(dev, EGL_DRM_DEVICE_FILE_EXT / _RENDER_NODE_FILE_EXT)
 * to match the node it is bringing up. Tegra's NVIDIA EGL advertises
 * EGL_EXT_device_base but eglQueryDevicesEXT BAD_ALLOCs (no EGL device
 * platform), so the match fails -> "Unable to find matching egl device for
 * /dev/dri/card0" -> the compositor starts with no output. kmscube avoids this
 * by using pure GBM.
 *
 * Report ONE synthetic EGL device whose DRM node is card0 and whose render node
 * is renderD128, so smithay's matching succeeds. Rendering still runs through
 * the GBM EGLDisplay (which works once the /dev/nvgpu tree is accessible).
 *
 * EGL extension entry points are resolved via eglGetProcAddress, not direct
 * linking, so we MUST hook eglGetProcAddress too (a plain symbol override is
 * not enough). Inert for any process that does not query these names.
 *
 * Node paths are fixed for this Orin gui-vm build (card0 = nvdisplay, renderD128
 * = nvgpu render node); override with EGL_SHIM_CARD / EGL_SHIM_RENDER if they
 * ever move.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

typedef void *EGLDeviceEXT;
typedef unsigned int EGLBoolean;
typedef int EGLint;
typedef void (*__egl_proc)(void);

#define EGL_TRUE 1
#define EGL_FALSE 0
#define EGL_DRM_DEVICE_FILE_EXT 0x3233
#define EGL_DRM_RENDER_NODE_FILE_EXT 0x3377
#define EGL_EXTENSIONS 0x3055

/* Distinct, non-NULL sentinel used as our one EGLDeviceEXT handle. */
static int egl_shim_dev_obj;
#define SHIM_DEV ((EGLDeviceEXT)&egl_shim_dev_obj)

static const char *card_node(void) {
  const char *e = getenv("EGL_SHIM_CARD");
  return (e && *e) ? e : "/dev/dri/card0";
}
static const char *render_node(void) {
  const char *e = getenv("EGL_SHIM_RENDER");
  return (e && *e) ? e : "/dev/dri/renderD128";
}

EGLBoolean eglQueryDevicesEXT(EGLint max_devices, EGLDeviceEXT *devices,
                              EGLint *num_devices) {
  if (!num_devices)
    return EGL_FALSE;
  if (!devices) { /* count query */
    *num_devices = 1;
    return EGL_TRUE;
  }
  if (max_devices < 1) {
    *num_devices = 0;
    return EGL_TRUE;
  }
  devices[0] = SHIM_DEV;
  *num_devices = 1;
  return EGL_TRUE;
}

const char *eglQueryDeviceStringEXT(EGLDeviceEXT device, EGLint name) {
  if (device == SHIM_DEV) {
    switch (name) {
    case EGL_DRM_DEVICE_FILE_EXT:
      return card_node();
    case EGL_DRM_RENDER_NODE_FILE_EXT:
      return render_node();
    case EGL_EXTENSIONS:
      return "EGL_EXT_device_drm EGL_EXT_device_drm_render_node";
    default:
      return "";
    }
  }
  const char *(*real)(EGLDeviceEXT, EGLint) =
      (const char *(*)(EGLDeviceEXT, EGLint))dlsym(RTLD_NEXT,
                                                   "eglQueryDeviceStringEXT");
  return real ? real(device, name) : "";
}

__egl_proc eglGetProcAddress(const char *name) {
  if (name) {
    if (!strcmp(name, "eglQueryDevicesEXT"))
      return (__egl_proc)eglQueryDevicesEXT;
    if (!strcmp(name, "eglQueryDeviceStringEXT"))
      return (__egl_proc)eglQueryDeviceStringEXT;
  }
  __egl_proc (*real)(const char *) =
      (__egl_proc(*)(const char *))dlsym(RTLD_NEXT, "eglGetProcAddress");
  return real ? real(name) : (__egl_proc)0;
}
