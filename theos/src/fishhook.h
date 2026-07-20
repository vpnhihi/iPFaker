// Minimal fishhook (Facebook BSD) — rebind imports in loaded images
#ifndef IPF_FISHHOOK_H
#define IPF_FISHHOOK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct rebinding {
  const char *name;
  void *replacement;
  void **replaced;
};

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);

#ifdef __cplusplus
}
#endif

#endif
