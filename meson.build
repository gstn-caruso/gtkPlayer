project('gtkplayer', 'vala', 'c', 'cpp', version: '0.1.0', meson_version: '>=1.0')
core_deps = [dependency('gio-2.0'), dependency('gstreamer-1.0'), dependency('gstreamer-pbutils-1.0'), dependency('gstreamer-audio-1.0')]
# projectM 4.1 targets framebuffer 0. The pinned private build preserves GTK's
# framebuffer (see the compatibility patch in subprojects/packagefiles/projectm).
cmake = import('cmake')
projectm_options = cmake.subproject_options()
projectm_options.add_cmake_defines({'ENABLE_PLAYLIST': false, 'ENABLE_SDL_UI': false, 'BUILD_TESTING': false, 'BUILD_DOCS': false, 'ENABLE_SYSTEM_PROJECTM_EVAL': false, 'ENABLE_DEBUG_POSTFIX': false, 'ENABLE_INSTALL': true, 'BUILD_SHARED_LIBS': true})
projectm_project = cmake.subproject('projectm', options: projectm_options)
projectm = projectm_project.dependency('gtkplayer_projectM')
# Meson disallows install_data across subproject boundaries. Keep complete
# upstream source and notices using its DESTDIR-aware install hook instead.
python = import('python').find_installation('python3')
meson.add_install_script(python, meson.project_source_root() / 'tools/install-projectm.py', meson.project_source_root(), get_option('datadir'))
photo_deps = [dependency('gio-2.0'), dependency('libsoup-3.0'), dependency('json-glib-1.0')]
photo_sources = files('src/artist-photos.vala')
photo_tests = executable('artist-photos-tests', photo_sources, 'tests/artist-photos-tests.vala', dependencies: photo_deps)
test('artist-photos', photo_tests, timeout: 15)
ui_deps = core_deps + [dependency('gtk4', version: '>=4.10'), dependency('libadwaita-1', version: '>=1.4')]
renderer = static_library('visualizer-renderer', 'src/visualizer-renderer.c', dependencies: [core_deps, dependency('epoxy'), projectm])
visualizer_sources = files('src/visualizer.vala', 'src/visualizer-renderer.vapi')
source_includes = include_directories('src')
core = files('src/library.vala', 'src/queue.vala', 'src/session.vala', 'src/player.vala', 'src/settings.vala', 'src/audio-tap.vapi', 'src/audio-tap.c')
core_tests = executable('core-tests', core, 'tests/core-tests.vala', include_directories: source_includes, dependencies: core_deps)
test('core', core_tests, timeout: 60)
executable('gtkplayer', core, photo_sources, visualizer_sources, 'src/browser.vala', 'src/window.vala', 'src/main.vala', link_with: renderer, include_directories: source_includes, dependencies: ui_deps + photo_deps, install: true)
install_data('data/io.github.gtkplayer.Player.desktop', install_dir: get_option('datadir') / 'applications')
ui_tests = executable('ui-tests', core, photo_sources, visualizer_sources, 'src/browser.vala', 'src/window.vala', 'tests/ui-tests.vala', link_with: renderer, include_directories: source_includes, dependencies: ui_deps + photo_deps)
xvfb = find_program('xvfb-run')
test('ui', xvfb, args: ['-a', '-s', '-screen 0 1920x1080x24', ui_tests], env: ['GDK_BACKEND=x11', 'GSETTINGS_BACKEND=memory', 'GTK_A11Y=none', 'GSK_RENDERER=cairo', 'GIO_USE_VFS=local'], timeout: 90)
