# Package

version       = "0.2.0"
author        = "PMunch"
description   = "Simple program to show notifications with images and actions around the screen"
license       = "MIT"
srcDir        = "src"
bin           = @["notifishower"]



# Dependencies

requires "nim >= 1.2.6"
requires "docopt"
requires "imlib2"
requires "https://github.com/PMunch/x11#monitors"
requires "npeg"
requires "kiwi"
#requires "x11"
