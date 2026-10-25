project('gtkplayer', 'vala', 'c', version: '0.1.0', meson_version: '>=1.0')
core_deps = [dependency('gio-2.0'), dependency('gstreamer-1.0'), dependency('gstreamer-pbutils-1.0')]
ui_deps = core_deps + [dependency('gtk4', version: '>=4.10'), dependency('libadwaita-1', version: '>=1.4')]
core = files('src/library.vala', 'src/queue.vala', 'src/player.vala', 'src/settings.vala')
core_tests = executable('core-tests', core, 'tests/core-tests.vala', dependencies: core_deps)
test('core', core_tests, timeout: 60)
executable('gtkplayer', core, 'src/window.vala', 'src/main.vala', dependencies: ui_deps, install: true)
install_data('data/io.github.gtkplayer.Player.desktop', install_dir: get_option('datadir') / 'applications')
ui_tests = executable('ui-tests', core, 'src/window.vala', 'tests/ui-tests.vala', dependencies: ui_deps)
xvfb = find_program('xvfb-run')
test('ui', xvfb, args: ['-a', ui_tests], env: ['GDK_BACKEND=x11', 'GSETTINGS_BACKEND=memory', 'GTK_A11Y=none', 'GSK_RENDERER=cairo'], timeout: 30)
