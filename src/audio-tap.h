#pragma once
#include <gst/gst.h>
typedef struct MusicAudioTap MusicAudioTap;
MusicAudioTap *music_audio_tap_new (void);
void music_audio_tap_free (MusicAudioTap *self);
GstElement *music_audio_tap_get_filter (MusicAudioTap *self);
gboolean music_audio_tap_get_available (MusicAudioTap *self);
void music_audio_tap_enable (MusicAudioTap *self, gboolean enabled);
guint8 *music_audio_tap_read (MusicAudioTap *self, gint *length);
