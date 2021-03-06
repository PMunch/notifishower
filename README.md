![Notifishower logo](https://github.com/PMunch/notifishower/blob/master/notifishower.png)

Ever wanted to just display some information on the screen in your custom Linux
environment. Or just have full control over your notifications? Then this is
the tool for you!

# What is notifishower?
Notifishower is a simple program to display a combination of text and images as
a notification, a dock, a desktop widget, or even just a normal window. The
goal is to be as flexible as absolutely possible, with layouts defined in a
EVFL-like formatting language and full ninepatch support for the background and
elements. It also supports clickable elements, keyboard shortcuts, and updating
text and images while the program is running. It does not read freedesktop
notifications however, for that you might want to check out notificatcher.

# Sounds cool, how do I use it?
Easiest way to figure it out is by checking out the help message:

```
Notifishower 0.7.0

This is a simple program to display a combinations of text and images as a
notification on the screen. It does not read freedesktop notifications, for
that you might want to check out notificatcher.

Usage:
  notifishower [options]

Options:
  --help                                    Show this screen
  -v --version                              Show the version
  --config <file>                           Parses options from the config file
  --class <class>                           Set the window class [default: notishower]
  --name <name>                             Set the window name [default: Notishower]
  --icon <file>                             Set the window icon
  --mode <mode>                             Decides the mode of the X11 window [default: notification]
  --edge <edge>                             The side on which to attach the dock when in docking mode
  -x <x>                                    Set the x position of the notification [default: 0]
  -y <y>                                    Set the y position of the notification [default: 0]
  -w <w>                                    Set the width of the notification [default: 200]
  -h <h>                                    Set the height of the notification [default: 100]
  --color <color>                           Set the default colour of all text
  --background <color>                      Set the background colour of the notification
  --hover <color>                           Set the default colour of the hover indicator
  --border <color>                          Set the border colour of the notification
  --border.width <bw>                       Set the width of the border [default: 2]
  --font <font>                             Sets the default font for all text elements
  --action <action>                         Assign an action to clicks outside any element
  --quitonaction                            Wheter or not to quit when an action is taken [default: true]
  --ninepatch <path>                        Set the background to a ninepatch image
  --tile <bool>                             Set the ninepatch to tiling mode or not
  --shortcut <shortcut>                     Sets a keyboard shortcut for the default action
  --<id>.text <text>                        Store a text element with a given ID
  --<id>.text.pipe <path>                   A file or fifo which will be used for text input
  --<id>.font <font>                        Set the font for a text element
  --<id>.color <color>                      Set the color for a text element
  --<id>.background <color>                 Set the background color for an element
  --<id>.image <path>                       Store an image element with a given ID
  --<id>.image.pipe <path>                  A file or fifo which will be used for image input
  --<id>.ninepatch <path>                   Set the background of an element to a ninepatch
  --<id>.tile <bool>                        Set the tiling mode of the background ninepatch
  --<id>.action <action>                    Assign an action to an element
  --<id>.hover <color>                      Set the color of the hover indicator
  --<id>.hover.ninepatch <path>             Set the hover indicator of an element to a ninepatch
  --<id>.hover.tile <bool>                  Set the tiling mode of the hover indicator ninepatch
  --<id>.shortcut <shortcut>                Adds a keyboard shortcut to run the element action
  --monitor <xrandrID> [<x>,<y>] [<w>:<h>]  Defines a monitor to show the notification on
  --format <format>                         Sets the layout of the notification
  --padding <number>                        The default padding for '-' in a pattern
  --timeout <number>                        Close the notification after a number of seconds

Mode:
  Notifishower was originally made to show notifications on screen. However its
  customisability quickly led it to be useful for other things. With the mode
  switch you are able to tell notifishower to display in different modes. The
  mode can be one of "notification", "desktop", "window", or "dock".
  Notification is the default, and will show a borderless window that draws on
  top of everything else. Desktop does the same, but draws underneath all other
  windows, effectively acting as a desktop widget. Window is a typical window,
  and is under full control of the WM. And finally dock will request an edge of
  the monitor where windows don't show and display there.

Piping input:
  With the pipe variants of text and images you can update the content of fields
  passed to the notification. Particularily useful for docks or desktop widgets.
  The input is polled by select and each line read and used as the input.
  Because of this it is a good idea to make a FIFO instead of passing a file so
  that the contents won't accumulate.

Positions and widths:
  X and Y positions can be the position on the monitor to display the
  notification, if you pass a negative number it will be placed that many pixels
  minus one away from the right or bottom. The minus one is because -0 isn't a
  valid number for the parser so -1 is the same as 0 pixels from the edge. In
  addition you can use center+/-<number> to center the notification in the x or
  y direction. Passing center+0 for both x and y should put the center of the
  notification in the center of your screen.
  Width and height can also be negative, and it means screen width minus
  that amount. For width and height you're also able to define >= or <=
  constraints so -w >=100 would set the minimal size of the notification to
  100 but otherwise scale it larger.
  Border width is applied outside the window, so setting width to 100 and border
  width to 50 would still mean a 100 pixel area for the notification.

Colors:
  Colors are simple hex colors, with an optional # prefix. If a six character
  value is passed alpha is assumed to be FF, or if an eight character value is
  passed then the last two characters are considered the alpha value.

Ninepatch background:
  In order to be better able to customise the appearance of notifications
  notifishower also supports ninepatch background images. Ninepatches are normal
  images with a 1px border around the entire image, this border contains
  contiguous black pixels that signify which parts of the image can be
  stretched, and where to place content. When setting width and height of the
  notification it will be the width and height of the notification including the
  area required for padding in the ninepatch image, so your actual content area
  might be smaller. If you want the scaleable section to tile instead of stretch
  you can pass the --tile true option.
  Ninepatches can also be applied as background to any element. This is done by
  passing --<id>.ninepatch and similarily --<id>.tile. Unlike the global
  ninepatch background this draws the ninepatch outside the element so if you
  want to make sure it doesn't appear under other elements or collide with other
  backgrounds you need to supply your own padding in the format.

Fonts:
  Fonts are following the Imlib2 font format and are read from these folders:
    $HOME/.local/share/fonts
    $HOME/.fonts
    /usr/local/share/fonts
    /usr/share/fonts/truetype
    /usr/share/fonts/truetype/dejavu
    /usr/share/fonts/TTF
  The format is essentially the filename without the ".ttf" extension followed
  by a slash and the size, e.g. DejaVuSans/20 to load the file DejaVuSans.ttf
  from one of those folders at point 20 size.

Layout format:
  In order to give you the ultimate configuration ability notifishower
  implements a fairly simple visual formatting language. It features the
  following grammar elements:
    []       <- A group of vertical elements
    ()       <- A group of horizontal elements
    -        <- A bit of padding
    ~        <- An expanding bit of padding
    <label>  <- An item that will be laid out
    <label>= <- Prefaces a group to name it
    :        <- The start of a constraint
  The default pattern is:
    (-[~icon:32~]-[~title body~]-)
  Which means a horizontal stack with padding before, after, and between two
  vertical sub-groups. The first sub-group contains the "icon" with expanding
  padding above and below (meaning it will be vertically centered). It also has
  a constrained size of 32 pixels in height (it will be scaled by aspect ratio
  to match). The second sub-group contains the "title" and "body" without
  padding between them and centered vertically in the group.
  The labels are defined by the --<id>.text and --<id>.image options.
  Constraints can be either a number or a label, optinonally prefixed by ">=" or
  "<=" to specify if it's exact, or larger or greater than. When a constraint is
  an element it constrains the size of this element in relation to that element.
  It can also be a percentage postfixed by "%" which will be a percentage of the
  size of the containing group. All constraints apply to the direction of the
  parent container.  To specify a width of a padding you can put a constraint in
  the middle of two "-" characters, for example '-10-', '->=20-', or '-5%-'.
  When using this format make sure that all your constraints are actually
  achievable, if not a notification will not be shown. Also make sure that you
  have sufficient expanding padding regions to take up any remaining space in
  the layout.

Clickable elements:
  Elements can be made clickable by assigning them an action. This is done by
  passing --<id>.action. When an element that has an action is clicked it will
  write the action to stdout and close the notification (unless --quitonaction
  is set to false). When an element that has an action is hovered by the mouse
  it will paint a rectangle underneath itself in either the default hover color
  or the color defined with --<id>.hover. If you want to add a ninepatch image
  instead as the hover background you can use --<id>.hover.ninepatch and
  --<id>.hover.tile to specify the image and the tiling mode. If a group is
  named that entire group can also be made clickable in the same way as
  elements. The action can also include a certain set of format strings,
  {clickX} and {clickY} which is the position of the click relative to the
  element, {elementX} and {elementY} which is the position of the element within
  the root window, {rootX} and {rootY} which is the position of the click within
  the root window, {trigger} which is either click or keyboard, and {value}
  which is the current text or image that was clicked.

Shortcuts:
  Elements with an action can also be assigned a shortcut. You can pass
  --<id>.shortcut and a shortcut containing zero or more modifiers followed by a
  key name, separated by '+' symbols. For example 'ctrl+shift+b' or
  'XF86Search'. When the shortcut is pressed the action will be triggered the
  same way as if the element was clicked.
  The modifiers can be:
    ctrl
    shift
    lock
    mod1
    mod2
    mod3
    mod4
    mod5
  They can all be remapped in your X11 configuration, to see what they are
  bound to, you can run 'xmodmap -pm' to print the modifier map.

Monitors:
  By default a notification will be shown on all available monitors. If you
  want to define which monitors to show the notification on you can pass the
  --monitor parameter with an identifier from xrandr. If you specify one then
  you have to specify every monitor you want to display the notification on.
  You can also pass the position as x,y or the width as w:h following the same
  rule as the global parameters.

Configuration file:
  A configuration file is also supported. Is is essentially just a string
  transformation of the configuration file into the command line options. The
  format is simply options without the preceding dashes, followed by a colon,
  and the value as bash would parse it. This is how the default.conf file
  appears and contains all the default parameters:
    color: #FFFFFF
    background: #444444
    border: #808080
    border.width: 2
    x: 49
    y: 0
    w: -98
    h: >=0
    font: DejaVuSans/10
    format: (-[~icon:32~]-[~title body~]-)
    title.font: DejaVuSans/12

Managing notifications:
  By default notifishower doesn't have any keyboard shortcuts to close the
  notification or any timeout method to remove them. In order to remove the
  notification you must kill the process, so it might be a good idea to add a
  "killall notifishower" shortcut to your window manager. It also doesn't
  support getting notifications from freedesktop, for that you might want to
  have a look at notificatcher.
```
