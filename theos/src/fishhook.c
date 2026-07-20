// Minimal fishhook for arm64/arm64e — based on Facebook fishhook (BSD)
#include "fishhook.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH LC_SEGMENT
#endif

static struct rebinding *g_rebindings = NULL;
static size_t g_rebindings_nel = 0;

static void perform_rebinding_with_section(section_t *sect, intptr_t slide, nlist_t *symtab,
                                           char *strtab, uint32_t *indirect) {
  uint32_t *indirect_sym = indirect + sect->reserved1;
  void **indirect_bindings = (void **)((uintptr_t)slide + sect->addr);
  for (uint32_t i = 0; i < sect->size / sizeof(void *); i++) {
    uint32_t symtab_index = indirect_sym[i];
    if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
        symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS))
      continue;
    uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
    char *symbol_name = strtab + strtab_offset;
    bool seen = false;
    // symbol_name starts with '_'
    if (symbol_name[0] != '_') continue;
    for (size_t j = 0; j < g_rebindings_nel; j++) {
      if (strcmp(&symbol_name[1], g_rebindings[j].name) != 0) continue;
      if (g_rebindings[j].replaced != NULL && indirect_bindings[i] != g_rebindings[j].replacement) {
        *(g_rebindings[j].replaced) = indirect_bindings[i];
      }
      indirect_bindings[i] = g_rebindings[j].replacement;
      seen = true;
      break;
    }
    (void)seen;
  }
}

static void rebind_for_image(const struct mach_header *header, intptr_t slide) {
  Dl_info info;
  if (dladdr(header, &info) == 0) return;

  segment_command_t *cur_seg = NULL;
  segment_command_t *linkedit = NULL;
  struct symtab_command *symtab_cmd = NULL;
  struct dysymtab_command *dysymtab_cmd = NULL;

  uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
  for (uint32_t i = 0; i < header->ncmds; i++, cur += cur_seg->cmdsize) {
    cur_seg = (segment_command_t *)cur;
    if (cur_seg->cmd == LC_SEGMENT_ARCH) {
      if (strcmp(cur_seg->segname, SEG_LINKEDIT) == 0) linkedit = cur_seg;
    } else if (cur_seg->cmd == LC_SYMTAB) {
      symtab_cmd = (struct symtab_command *)cur_seg;
    } else if (cur_seg->cmd == LC_DYSYMTAB) {
      dysymtab_cmd = (struct dysymtab_command *)cur_seg;
    }
  }
  if (!symtab_cmd || !dysymtab_cmd || !linkedit || !dysymtab_cmd->nindirectsyms) return;

  uintptr_t linkedit_base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
  nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
  char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
  uint32_t *indirect = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

  cur = (uintptr_t)header + sizeof(mach_header_t);
  for (uint32_t i = 0; i < header->ncmds; i++, cur += cur_seg->cmdsize) {
    cur_seg = (segment_command_t *)cur;
    if (cur_seg->cmd != LC_SEGMENT_ARCH) continue;
    if (strcmp(cur_seg->segname, SEG_DATA) != 0 && strcmp(cur_seg->segname, SEG_TEXT) != 0 &&
        strcmp(cur_seg->segname, "__DATA_CONST") != 0 && strcmp(cur_seg->segname, "__AUTH_CONST") != 0)
      continue;
    section_t *sects = (section_t *)(cur + sizeof(segment_command_t));
    for (uint32_t j = 0; j < cur_seg->nsects; j++) {
      section_t *sect = &sects[j];
      uint32_t flags = sect->flags & SECTION_TYPE;
      if (flags == S_LAZY_SYMBOL_POINTERS || flags == S_NON_LAZY_SYMBOL_POINTERS) {
        perform_rebinding_with_section(sect, slide, symtab, strtab, indirect);
      }
    }
  }
}

static void _rebind_symbols_for_image(const struct mach_header *header, intptr_t slide) {
  rebind_for_image(header, slide);
}

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
  // prepend
  size_t nel = g_rebindings_nel + rebindings_nel;
  struct rebinding *new_r = calloc(nel, sizeof(struct rebinding));
  if (!new_r) return -1;
  memcpy(new_r, rebindings, sizeof(struct rebinding) * rebindings_nel);
  if (g_rebindings && g_rebindings_nel)
    memcpy(new_r + rebindings_nel, g_rebindings, sizeof(struct rebinding) * g_rebindings_nel);
  free(g_rebindings);
  g_rebindings = new_r;
  g_rebindings_nel = nel;

  uint32_t c = _dyld_image_count();
  for (uint32_t i = 0; i < c; i++) {
    rebind_for_image((const struct mach_header *)_dyld_get_image_header(i),
                     _dyld_get_image_vmaddr_slide(i));
  }
  _dyld_register_func_for_add_image(_rebind_symbols_for_image);
  return 0;
}
