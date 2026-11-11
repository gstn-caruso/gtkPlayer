namespace Music {
    public class ArtistPhoto : Object {
        public Bytes bytes { get; construct; }
        public string author { get; construct; }
        public string license_name { get; construct; }
        public string license_url { get; construct; }
        public string source_url { get; construct; }

        internal ArtistPhoto (Bytes bytes, string author, string license_name,
                              string license_url, string source_url) {
            Object (bytes: bytes, author: author, license_name: license_name,
                    license_url: license_url, source_url: source_url);
        }
    }

    // Owns the trust boundary: only public Wikimedia data, never library contents.
    public class ArtistPhotos : Object {
        private Soup.Session session;
        private string? test_origin;

        public ArtistPhotos () {
            session = new Soup.Session () {
                timeout = 10,
                user_agent = "gtkPlayer/0.1 (https://github.com/gstn-caruso/gtkPlayer; artist portraits)"
            };
        }

        // This exception cannot be used to configure a remote HTTP service.
        public ArtistPhotos.for_test_server (string loopback_origin) throws Error {
            this ();
            var uri = Uri.parse (loopback_origin, UriFlags.NONE);
            if (uri.get_scheme () != "http" ||
                !(uri.get_host () == "127.0.0.1" || uri.get_host () == "::1") ||
                uri.get_port () < 1 || uri.get_userinfo () != null ||
                uri.get_path () != "" || uri.get_query () != null || uri.get_fragment () != null)
                throw new IOError.INVALID_ARGUMENT ("El servidor de prueba debe ser un origen loopback");
            test_origin = loopback_origin;
        }

        private void validate_url (string url) throws Error {
            var uri = Uri.parse (url, UriFlags.NONE);
            if (uri.get_userinfo () != null || uri.get_fragment () != null)
                throw new IOError.INVALID_DATA ("Destino con credenciales o fragmento");
            if (test_origin != null) {
                var origin = Uri.parse (test_origin, UriFlags.NONE);
                if (uri.get_scheme () == origin.get_scheme () && uri.get_host () == origin.get_host () &&
                    uri.get_port () == origin.get_port ())
                    return;
            }
            if (uri.get_scheme () != "https" || (uri.get_port () != -1 && uri.get_port () != 443))
                throw new IOError.INVALID_DATA ("Se requiere HTTPS de Wikimedia");
            switch (uri.get_host ()) {
            case "en.wikipedia.org":
            case "commons.wikimedia.org":
            case "thumb.wikimedia.org":
            case "upload.wikimedia.org":
                return;
            default:
                throw new IOError.INVALID_DATA ("Destino fuera de Wikimedia");
            }
        }

        private async Bytes download (string url, bool image, Cancellable cancellable) throws Error {
            validate_url (url);
            var message = new Soup.Message ("GET", url);
            message.set_flags (Soup.MessageFlags.NO_REDIRECT);
            message.request_headers.replace ("Accept", image ? "image/jpeg, image/png, image/webp" : "application/json");
            var stream = yield session.send_async (message, Priority.DEFAULT, cancellable);
            var data = new ByteArray ();
            try {
                if (message.status_code != 200)
                    throw new IOError.FAILED ("Respuesta HTTP %u", message.status_code);
                string? mime = message.response_headers.get_content_type (null);
                if ((!image && mime != "application/json") ||
                    (image && mime != "image/jpeg" && mime != "image/png" && mime != "image/webp"))
                    throw new IOError.INVALID_DATA ("Tipo de respuesta inesperado");
                size_t limit = image ? 5 * 1024 * 1024 : 1024 * 1024;
                if (message.response_headers.get_content_length () > (int64) limit)
                    throw new IOError.INVALID_DATA ("Respuesta demasiado grande");
                while (true) {
                    var chunk = yield stream.read_bytes_async (16384, Priority.DEFAULT, cancellable);
                    if (chunk.get_size () == 0) break;
                    if (data.len + chunk.get_size () > limit)
                        throw new IOError.INVALID_DATA ("Respuesta demasiado grande");
                    data.append (chunk.get_data ());
                }
                if (data.len == 0)
                    throw new IOError.INVALID_DATA ("Respuesta vacía");
            } catch (Error e) {
                try {
                    yield stream.close_async (Priority.DEFAULT, null);
                } catch (Error close_error) {
                    // Preserve the original download failure.
                }
                throw e;
            }
            yield stream.close_async (Priority.DEFAULT, null);
            return ByteArray.free_to_bytes ((owned) data);
        }

        private async Json.Object read_json (string url, Cancellable cancellable) throws Error {
            var bytes = yield download (url, false, cancellable);
            var parser = new Json.Parser ();
            unowned uint8[] data = bytes.get_data ();
            parser.load_from_data ((string) data, (ssize_t) data.length);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                throw new IOError.INVALID_DATA ("Se esperaba un objeto JSON");
            return root.get_object ();
        }

        private static Json.Node member (Json.Object object, string name, Json.NodeType type) throws Error {
            if (!object.has_member (name))
                throw new IOError.INVALID_DATA ("Campo JSON ausente: %s", name);
            var node = object.get_member (name);
            if (node == null || node.get_node_type () != type)
                throw new IOError.INVALID_DATA ("Campo JSON inválido: %s", name);
            return node;
        }

        private static string text (Json.Object object, string name) throws Error {
            var node = member (object, name, Json.NodeType.VALUE);
            if (node.get_value_type () != typeof (string) || node.get_string () == null)
                throw new IOError.INVALID_DATA ("Se esperaba texto: %s", name);
            return node.get_string ();
        }

        private static Json.Object object_member (Json.Object object, string name) throws Error {
            return member (object, name, Json.NodeType.OBJECT).get_object ();
        }

        private static string normalized (string title) {
            return title.replace ("_", " ").strip ().normalize ().casefold ();
        }

        // Conservative summary evidence, not proof of a MusicBrainz identity.
        private static bool has_musical_description (Json.Object summary) throws Error {
            if (!summary.has_member ("description")) return false;
            var description = summary.get_member ("description");
            if (description == null || description.get_node_type () != Json.NodeType.VALUE ||
                description.get_value_type () != typeof (string)) return false;
            // Require an occupation/group near the start, not a mention of music
            // elsewhere in a city description or a suggestive image filename.
            var musical = new Regex ("(?i)^(?:[\\p{L}-]+\\s+){0,3}(?:singer(?:-songwriter)?|songwriter|musician|composer|rapper|pianist|guitarist|bassist|drummer|vocalist|conductor|(?:rock|jazz|pop|punk|metal|folk|blues|musical)[ -]band|musical group|orchestra)\\b");
            return musical.match (description.get_string ());
        }

        private static string normalized_file_title (string title) {
            return title.replace ("_", " ").normalize (-1, NormalizeMode.DEFAULT_COMPOSE);
        }

        private static string metadata (Json.Object metadata, string name) throws Error {
            return text (object_member (metadata, name), "value");
        }

        // Produce plain text, not markup to pass to a UI renderer.
        private static string plain_author (string html) throws Error {
            var scripts = new Regex ("(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>");
            var tags = new Regex ("<[^>]*>");
            string plain = tags.replace (scripts.replace (html, -1, 0, ""), -1, 0, "");
            var entities = new Regex ("&#(x[0-9a-fA-F]+|[0-9]+);");
            plain = entities.replace_eval (plain, -1, 0, 0, (match, result) => {
                string value = match.fetch (1);
                uint64 code;
                if (uint64.try_parse (value.has_prefix ("x") ? value.substring (1) : value,
                                      out code, null, value.has_prefix ("x") ? 16 : 10) &&
                    code > 0 && code <= 0x10ffff && ((unichar) code).validate ())
                    result.append_unichar ((unichar) code);
                else result.append (match.fetch (0));
                return false;
            });
            return plain.replace ("&lt;", "<").replace ("&gt;", ">").replace ("&quot;", "\"")
                        .replace ("&apos;", "'").replace ("&#39;", "'").replace ("&nbsp;", " ")
                        .replace ("&amp;", "&").strip ();
        }

        private static bool permitted_license (string name, string url) throws Error {
            var uri = Uri.parse (url, UriFlags.NONE);
            if (uri.get_scheme () != "https" || uri.get_host () != "creativecommons.org" ||
                uri.get_port () != -1 || uri.get_userinfo () != null ||
                uri.get_query () != null || uri.get_fragment () != null) return false;
            var cc = new Regex ("^CC BY(-SA)? (1\\.0|2\\.0|2\\.5|3\\.0|4\\.0)(?: ([a-z]{2}))?$");
            MatchInfo match;
            if (cc.match (name, 0, out match)) {
                string kind = match.fetch (1) == "-SA" ? "by-sa" : "by";
                string path = "/licenses/" + kind + "/" + match.fetch (2);
                string country = match.fetch (3);
                if (country != "") path += "/" + country;
                if (uri.get_path () == path || uri.get_path () == path + "/") return true;
                var deed = new Regex ("^" + Regex.escape_string (path) + "/deed\\.[a-z]{2,3}(?:[_-][A-Za-z]{2,4})?$");
                return deed.match (uri.get_path ());
            }
            return (name == "CC0" && uri.get_path () == "/publicdomain/zero/1.0/") ||
                   (name == "Public domain" && (uri.get_path () == "/publicdomain/mark/1.0/" ||
                                               uri.get_path () == "/publicdomain/zero/1.0/"));
        }

        public async ArtistPhoto? fetch (string artist, Cancellable cancellable) throws Error {
            if (artist.strip () == "") return null;
            var operation = new Cancellable ();
            ulong cancellation = cancellable.connect (() => operation.cancel ());
            uint deadline = 0;
            deadline = Timeout.add_seconds (10, () => {
                deadline = 0;
                operation.cancel ();
                return Source.REMOVE;
            });
            try {
                return yield fetch_portrait (artist, operation);
            } finally {
                if (deadline != 0) Source.remove (deadline);
                cancellable.disconnect (cancellation);
            }
        }

        private async ArtistPhoto? fetch_portrait (string artist, Cancellable cancellable) throws Error {
            string wikipedia = test_origin ?? "https://en.wikipedia.org";
            string commons = test_origin ?? "https://commons.wikimedia.org";
            var summary = yield read_json (wikipedia + "/api/rest_v1/page/summary/" +
                                           Uri.escape_string (artist, null, false), cancellable);
            if (text (summary, "type") != "standard" ||
                normalized (text (summary, "title")) != normalized (artist) ||
                !has_musical_description (summary)) return null;
            if (!summary.has_member ("thumbnail") || !summary.has_member ("originalimage")) return null;
            string original = text (object_member (summary, "originalimage"), "source");
            validate_url (original);
            var original_uri = Uri.parse (original, UriFlags.NONE);
            string? filename = Uri.unescape_string (Path.get_basename (original_uri.get_path ()));
            if (filename == null || filename == "" || filename.contains ("/") || filename.contains ("\\"))
                throw new IOError.INVALID_DATA ("Nombre de imagen inválido");
            // Do not knowingly present album artwork as an artist portrait.
            string lower = filename.casefold ();
            if (lower.contains ("album") || lower.contains ("cover") || lower.contains ("logo")) return null;
            string title = "File:" + filename;
            var response = yield read_json (commons + "/w/api.php?action=query&format=json&prop=imageinfo" +
                "&iiprop=url%7Cextmetadata&iiurlwidth=320&titles=" + Uri.escape_string (title, null, false), cancellable);
            var pages = object_member (object_member (response, "query"), "pages");
            if (pages.get_size () != 1) return null;
            Json.Object? page = null;
            foreach (string key in pages.get_members ()) page = object_member (pages, key);
            if (page == null || page.has_member ("missing") ||
                normalized_file_title (text (page, "title")) != normalized_file_title (title)) return null;
            var ns = member (page, "ns", Json.NodeType.VALUE);
            var id = member (page, "pageid", Json.NodeType.VALUE);
            if (ns.get_value_type () != typeof (int64) || ns.get_int () != 6 ||
                id.get_value_type () != typeof (int64) || id.get_int () <= 0) return null;
            var infos = member (page, "imageinfo", Json.NodeType.ARRAY).get_array ();
            if (infos.get_length () != 1 || infos.get_element (0).get_node_type () != Json.NodeType.OBJECT)
                return null;
            var info = infos.get_object_element (0);
            string source = text (info, "descriptionurl");
            validate_url (source);
            var source_uri = Uri.parse (source, UriFlags.NONE);
            string? source_path = Uri.unescape_string (source_uri.get_path ());
            if (!(source.has_prefix (commons + "/wiki/File:")) || source_uri.get_query () != null ||
                source_path == null ||
                normalized_file_title (source_path) != "/wiki/" + normalized_file_title (title)) return null;
            var meta = object_member (info, "extmetadata");
            string license_name = metadata (meta, "LicenseShortName");
            string license_url = metadata (meta, "LicenseUrl");
            if (!permitted_license (license_name, license_url)) return null;
            string author = plain_author (metadata (meta, "Artist"));
            if (author == "") return null;
            string thumbnail = text (info, "thumburl");
            var bytes = yield download (thumbnail, true, cancellable);
            return new ArtistPhoto (bytes, author, license_name, license_url, source);
        }
    }
}
