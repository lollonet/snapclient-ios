/**
 * ios_controller_patch.hpp
 *
 * This header is included by controller.cpp when building for iOS.
 * It adds support for the IOSPlayer backend.
 *
 * Usage: Controller will automatically use IOSPlayer when HAS_IOS is defined.
 */

#pragma once

#ifdef IOS

// Include our iOS player
#include "ios_player/ios_player.hpp"

// Define HAS_IOS for the controller to pick up
#ifndef HAS_IOS
#define HAS_IOS 1
#endif

#endif // IOS
