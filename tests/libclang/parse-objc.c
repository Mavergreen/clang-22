/* platform: host-agnostic
 *   usage: parse-objc RESOURCE_DIR SDK FILE.m
 * Parses FILE.m for x86_64/10.9 through the shipped libclang, as shipyard's objc-source-inventory
 * does, and prints the clang version, the error count and how many of FILE.m's own message sends
 * resolved a receiver type. */
#include <clang-c/Index.h>
#include <stdio.h>

static enum CXChildVisitResult visit(CXCursor cursor, CXCursor parent, CXClientData data) {
  (void)parent;
  if (clang_getCursorKind(cursor) == CXCursor_ObjCMessageExpr &&
      clang_Location_isFromMainFile(clang_getCursorLocation(cursor)) &&
      clang_getCursorType(cursor).kind != CXType_Invalid &&
      clang_Cursor_getReceiverType(cursor).kind != CXType_Invalid)
    ++*(unsigned *)data;
  return CXChildVisit_Recurse;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  const char *args[] = {"-x", "objective-c", "-target", "x86_64-apple-macosx10.9",
                        "-resource-dir", argv[1], "-isysroot", argv[2]};
  CXIndex index = clang_createIndex(0, 0);
  CXTranslationUnit unit = clang_parseTranslationUnit(index, argv[3], args,
      (int)(sizeof args / sizeof *args), NULL, 0, CXTranslationUnit_None);
  if (!unit) { fputs("parse-objc: no translation unit\n", stderr); return 1; }
  unsigned errors = 0, messages = 0;
  for (unsigned i = 0, n = clang_getNumDiagnostics(unit); i < n; ++i) {
    CXDiagnostic diagnostic = clang_getDiagnostic(unit, i);
    if (clang_getDiagnosticSeverity(diagnostic) >= CXDiagnostic_Error) {
      CXString text = clang_formatDiagnostic(diagnostic, clang_defaultDiagnosticDisplayOptions());
      fprintf(stderr, "%s\n", clang_getCString(text));
      clang_disposeString(text);
      ++errors;
    }
    clang_disposeDiagnostic(diagnostic);
  }
  clang_visitChildren(clang_getTranslationUnitCursor(unit), visit, &messages);
  CXString version = clang_getClangVersion();
  printf("%s\nerrors=%u messages=%u\n", clang_getCString(version), errors, messages);
  clang_disposeString(version);
  clang_disposeTranslationUnit(unit);
  clang_disposeIndex(index);
  return 0;
}
