import imlib2

type
  Ninepatch* = object
    image*: string
    tile*, snap*: bool
    imgW*: cint
    imgH*: cint
    startX, startY, height, width: cint
    startDX*, startDY*, dheight*, dwidth*: cint
    widths: array[3, cint]
    heights: array[3, cint]

proc imlib_load_ninepatch*(path: string): Ninepatch =
  let black = ImlibColor(alpha: 255, red: 0, green: 0, blue: 0)
  var ninepatch = imlib_load_image(path)
  if ninepatch != nil:
    imlib_context_set_image(ninepatch)
    result.image = path
    result.imgW = imlib_image_get_width()
    result.imgH = imlib_image_get_height()
    result.dheight = result.imgH
    result.dwidth = result.imgW
    for x in 0..imlib_image_get_width():
      var color: ImlibColor
      imlib_image_query_pixel(x, 0, color.addr)
      if color == black:
        if result.startX == 0:
          result.startX = x
        if result.startX != 0:
          inc result.width
      imlib_image_query_pixel(x, result.imgH - 1, color.addr)
      if color == black:
        if result.startDX == 0:
          result.startDX = x
        if result.startDX != 0:
          dec result.dwidth
    for y in 0..imlib_image_get_height():
      var color: ImlibColor
      imlib_image_query_pixel(0, y, color.addr)
      if color == black:
        if result.startY == 0:
          result.startY = y
        if result.startY != 0:
          inc result.height
      imlib_image_query_pixel(result.imgW - 1, y, color.addr)
      if color == black:
        if result.startDY == 0:
          result.startDY = y
        if result.startDY != 0:
          dec result.dheight

    result.widths = [result.startX - 1, result.width, result.imgW - 1 - result.startX - result.width]
    result.heights = [result.startY - 1, result.height, result.imgH - 1 - result.startY - result.height]

    result.dwidth -= result.startDX + 1
    result.dheight -= result.startDY + 1
    result.startDX -= 1
    result.startDY -= 1
    imlib_free_image()

proc imlib_ninepatch_draw*(np: Ninepatch, x, y, w, h: cint) =
    imlib_context_set_anti_alias(0)
    var
      cw = w - np.widths[0] - np.widths[2]
      ch = h - np.heights[0] - np.heights[2]
      lh = ch mod np.heights[1]
      lw = cw mod np.widths[1]
      ninepatch = imlib_load_image(np.image)
    if ninepatch.isNil: return
    if np.snap:
      ch -= lh
      cw -= lw
    imlib_blend_image_onto_image(ninepatch, 1, 1, 1, np.widths[0], np.heights[0], x, y, np.widths[0], np.heights[0])
    imlib_blend_image_onto_image(ninepatch, 1, np.startX + np.widths[1], 1, np.widths[2], np.heights[0], x + np.widths[0] + cw, y, np.widths[2], np.heights[0])
    if np.tile:
      for i in countup(0.cint, cw - np.widths[1], np.widths[1]):
        imlib_blend_image_onto_image(ninepatch, 1, np.startX, 1, np.widths[1], np.heights[0], x + np.widths[0] + i, y, np.widths[1], np.heights[0])
        imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY + np.heights[1], np.widths[1], np.heights[2], x + np.widths[0] + i, y + np.heights[0] + ch, np.widths[1], np.heights[2])
        for ii in countup(0.cint, ch - np.heights[1], np.heights[1]):
          imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY, np.widths[1], np.heights[1], x + np.widths[0] + i, y + np.heights[0] + ii, np.widths[1], np.heights[1])
      for i in countup(0.cint, ch - np.heights[1], np.heights[1]):
        imlib_blend_image_onto_image(ninepatch, 1, 1, np.startY, np.widths[0], np.heights[1], x, y + np.heights[0] + i, np.widths[0], np.heights[1])
        imlib_blend_image_onto_image(ninepatch, 1, np.startX + np.widths[1], np.startY, np.widths[2], np.heights[1], x + np.widths[0] + cw, y + np.heights[0] + i, np.widths[2], np.heights[1])
      if not np.snap:
        imlib_blend_image_onto_image(ninepatch, 1, np.startX, 1, lw, np.heights[0], x + np.widths[0] + cw - lw, y, lw, np.heights[0])
        imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY + np.heights[1], lw, np.heights[2], x + np.widths[0] + cw - lw, y + np.heights[0] + ch, lw, np.heights[2])

        for i in countup(0.cint, cw - np.widths[1], np.widths[1]):
          imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY, np.widths[1], lh, x + np.widths[0] + i, y + np.heights[0] + ch - lh, np.widths[1], lh)
        for i in countup(0.cint, ch - np.heights[1], np.heights[1]):
          imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY, lw, np.heights[1], x + np.widths[0] + cw - lw, y + np.heights[0] + i, lw, np.heights[1])
        imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY, lw, lh, x + np.widths[0] + cw - lw, y +  np.heights[0] + ch - lh, lw, lh)

        imlib_blend_image_onto_image(ninepatch, 1, 1, np.startY, np.widths[0], lh, x, y + np.heights[0] + ch - lh, np.widths[0], lh)
        imlib_blend_image_onto_image(ninepatch, 1, np.startX + np.widths[1], np.startY, np.widths[2], lh, x + np.widths[0] + cw, y + np.heights[0] + ch - lh, np.widths[2], lh)

    else:
      imlib_blend_image_onto_image(ninepatch, 1, np.startX, 1, np.widths[1], np.heights[0], x + np.widths[0], y, cw, np.heights[0])
      imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY + np.heights[1], np.widths[1], np.heights[2], x + np.widths[0], y + np.heights[0] + ch, cw, np.heights[2])

      imlib_blend_image_onto_image(ninepatch, 1, np.startX, np.startY, np.widths[1], np.heights[1], x + np.widths[0], y + np.heights[0], cw, ch)

      imlib_blend_image_onto_image(ninepatch, 1, 1, np.startY, np.widths[0], np.heights[1] - 1, x, y + np.heights[0], np.widths[0], ch)
      imlib_blend_image_onto_image(ninepatch, 1, np.startX + np.widths[1], np.startY, np.widths[2], np.heights[1] - 1, x + np.widths[0] + cw, y + np.heights[0], np.widths[2], ch)

    imlib_blend_image_onto_image(ninepatch, 1, 1, np.startY + np.heights[1], np.widths[0], np.heights[2], x, y + np.heights[0] + ch, np.widths[0], np.heights[2])
    imlib_blend_image_onto_image(ninepatch, 1, np.startX + np.widths[1], np.startY + np.heights[1], np.widths[2], np.heights[2], x + np.widths[0] + cw, y + np.heights[0] + ch, np.widths[2], np.heights[2])
    imlib_context_set_image(ninepatch)
    imlib_free_image()
