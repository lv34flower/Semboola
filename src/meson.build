Semboola_sources = [
  'main.vala',
  'application.vala',
  'window.vala',
  'add_board.vala',
  'boards.vala',
  'threads.vala',
  'thread_row.vala',
  'ress.vala',
  'res_row.vala',
  'clickable_label.vala',
  'net/fivech.vala',
  'net/db.vala',
]

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
  meson.get_compiler('vala').find_library('posix'),
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
