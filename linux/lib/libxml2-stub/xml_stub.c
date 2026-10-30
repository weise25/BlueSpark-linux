/* A stand-in for libxml2.so.2, for LLVM's lld (the linker of LLVM 20.1.8's Linux release) where the system has no
 * libxml2.so.2: Steam's flatpak runtime since October 2026 (libxml2 2.15, libxml2.so.16), and distributions that
 * moved to libxml2 2.14+. lld loads libxml2 at its start but calls it only to merge Windows manifest files given with
 * /manifestinput, which the TTT2 build never does: lld writes its default manifest without it.
 *
 * Every function here does nothing and reports failure, so a call that did happen would make lld stop with an error
 * ("failed to parse the manifest"), never write something wrong. No libc: it loads on any glibc.
 *
 * Built by linux/lib/libxml2-stub/build.sh; linux/build.sh puts it on LD_LIBRARY_PATH only when lld can't start
 * without it. */

typedef unsigned long size_t;

#define STUB_PTR(name, ...) void *name(__VA_ARGS__) { return 0; }
#define STUB_VOID(name, ...) void name(__VA_ARGS__) {}

STUB_PTR(xmlAddChild, void *parent, void *cur)
STUB_PTR(xmlCopyNamespace, void *cur)
STUB_PTR(xmlDocGetRootElement, const void *doc)
STUB_PTR(xmlDocSetRootElement, void *doc, void *root)
STUB_PTR(xmlNewDoc, const unsigned char *version)
STUB_PTR(xmlNewNs, void *node, const unsigned char *href, const unsigned char *prefix)
STUB_PTR(xmlNewProp, void *node, const unsigned char *name, const unsigned char *value)
STUB_PTR(xmlStrdup, const unsigned char *cur)
STUB_PTR(xmlReadMemory, const char *buffer, int size, const char *url, const char *encoding, int options)
STUB_VOID(xmlFreeDoc, void *doc)
STUB_VOID(xmlFreeNode, void *node)
STUB_VOID(xmlFreeNs, void *ns)
STUB_VOID(xmlUnlinkNode, void *node)
STUB_VOID(xmlSetGenericErrorFunc, void *ctx, void *handler)

void xmlDocDumpFormatMemoryEnc(void *doc, unsigned char **mem, int *size, const char *encoding, int format) {
    if (mem) *mem = 0;
    if (size) *size = 0;
}

/* (In libxml2 xmlFree is a variable holding the free function.) */
static void free_nothing(void *p) {}
void (*xmlFree)(void *) = free_nothing;
