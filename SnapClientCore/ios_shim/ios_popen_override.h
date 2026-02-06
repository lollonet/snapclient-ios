/**
 * ios_popen_override.h — Force-included before all Snapcast source files.
 *
 * On iOS, popen() calls fork() which is restricted by the sandbox.
 * Depending on iOS version, fork() either returns -1 (safe) or triggers
 * EXC_GUARD (crash). To avoid any risk, we override popen() to always
 * return NULL, which Snapcast's execGetOutput() handles gracefully
 * (returns empty string).
 *
 * This only affects getOS() and getArch() in utils.hpp — they'll return
 * the uname() fallback ("Darwin") and empty string respectively.
 */

#pragma once

#ifdef IOS

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline FILE* ios_popen_safe(
    const char* cmd __attribute__((unused)),
    const char* mode __attribute__((unused)))
{
    return NULL;
}

#ifdef __cplusplus
}
#endif

/* Override popen so execGetOutput() in utils.hpp never calls fork(). */
#define popen ios_popen_safe

#endif /* IOS */
