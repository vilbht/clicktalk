# dmgbuild settings for the EucLink disk image. dmg/make.sh passes `app` and
# `background` with -D. Positions are in points from the window's top left and
# match dmg/background.html: the app sits in the rings, Applications at the arrow tip.
app = defines.get("app", "EucLink.app")  # noqa: F821 (dmgbuild provides `defines`)
background = defines.get("background", "dmg/background.png")  # noqa: F821

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {"EucLink.app": (165, 190), "Applications": (495, 190)}

window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
icon_size = 100
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
