Semboola_sources = [
  'main.vala',
  'application.vala',
  'window.vala',
  'ng.vala',
  'add_board.vala',
  'boards.vala',
  'thread_hist.vala',
  'threads.vala',
  'local_rules.vala',
  'new_thread.vala',
  'thread_row.vala',
  'ress.vala',
  'replies.vala',
  'res_row.vala',
  'imageview.vala',
  'new_res.vala',
  'clickable_label.vala',
  'cookie_confirm.vala',
  'net/fivech.vala',
  'net/db.vala',
  'common/common.vala',
  'common/image.vala',
  'subui/ng_sub.vala',
  'subui/ng_row.vala',
]

cc = meson.get_compiler('c')
libm = cc.find_library('m', required: true)

Semboola_deps = [
  config_dep,
  dependency('gtk4'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('gee-0.8'),
  dependency('sqlite3'),
  dependency('webkitgtk-6.0'),
  dependency('gdk-pixbuf-2.0'),
  meson.get_compiler('vala').find_library('posix'),
  libm,
]

Semboola_sources += gnome.compile_resources('Semboola-resources',
  'Semboola.gresource.xml',
  c_name: 'semboola'
)

executable('semboola', Semboola_sources,
  dependencies: Semboola_deps,
  include_directories: config_inc,
       install: true,
)
