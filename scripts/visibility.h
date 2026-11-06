/* Force-included into every libjxl translation unit. CMake's export headers
   leave these empty for static targets; the public API must stay visible so
   the single shared library can export it. */
#define JXL_EXPORT __attribute__((visibility("default")))
#define JXL_CMS_EXPORT __attribute__((visibility("default")))
#define JXL_THREADS_EXPORT __attribute__((visibility("default")))
