project('gtkplayer', 'vala', 'c', version: '0.1.0', meson_version: '>=1.0')
core_deps = [dependency('gio-2.0'), dependency('gstreamer-1.0'), dependency('gstreamer-pbutils-1.0')]
photo_deps = [dependency('gio-2.0'), dependency('libsoup-3.0'), dependency('json-glib-1.0')]
photo_sources = files('src/artist-photos.vala')
photo_tests = executable('artist-photos-tests', photo_sources, 'tests/artist-photos-tests.vala', dependencies: photo_deps)
test('artist-photos', photo_tests, timeout: 15)
ui_deps = core_deps + [dependency('gtk4', version: '>=4.10'), dependency('libadwaita-1', version: '>=1.4')]
core = files('src/library.vala', 'src/queue.vala', 'src/session.vala', 'src/player.vala', 'src/settings.vala')
core_tests = executable('core-tests', core, 'tests/core-tests.vala', dependencies: core_deps)
test('core', core_tests, timeout: 60)
executable('gtkplayer', core, photo_sources, 'src/browser.vala', 'src/window.vala', 'src/main.vala', dependencies: ui_deps + photo_deps, install: true)
install_data('data/io.github.gtkplayer.Player.desktop', install_dir: get_option('datadir') / 'applications')
ui_tests = executable('ui-tests', core, photo_sources, 'src/browser.vala', 'src/window.vala', 'tests/ui-tests.vala', dependencies: ui_deps + photo_deps)
xvfb = find_program('xvfb-run')
test('ui', xvfb, args: ['-a', '-s', '-screen 0 1920x1080x24', ui_tests], env: ['GDK_BACKEND=x11', 'GSETTINGS_BACKEND=memory', 'GTK_A11Y=none', 'GSK_RENDERER=cairo', 'GIO_USE_VFS=local'], timeout: 90)
