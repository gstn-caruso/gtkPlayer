namespace Music {
    // Only a location is persisted, never a library cache or authentication data.
    public class LocationSettings : Object {
        public const string DEFAULT_LOCATION = "smb://nas.local/public/multimedia/Música";
        private string path;
        public LocationSettings (string path) { this.path = path; }
        public static File parse_location (string input) throws Error {
            if (input.strip () == "") throw new IOError.INVALID_ARGUMENT ("Ingresá una carpeta local o una URI file:// o smb://.");
            var folder = File.new_for_commandline_arg (input.strip ());
            var uri = Uri.parse (folder.get_uri (), UriFlags.NONE);
            if (uri.get_userinfo () != null)
                throw new IOError.INVALID_ARGUMENT ("No incluyas credenciales en la URI. Usá el diálogo de autenticación del sistema.");
            if (uri.get_scheme () != "file" && uri.get_scheme () != "smb")
                throw new IOError.NOT_SUPPORTED ("Esta versión admite carpetas locales, file:// y smb://.");
            return folder;
        }
        public string load () {
            try {
                var key = new KeyFile ();
                key.load_from_file (path, KeyFileFlags.NONE);
                return parse_location (key.get_string ("Library", "location")).get_uri ();
            } catch (Error e) { return DEFAULT_LOCATION; }
        }
        public void save (string uri) throws Error {
            var folder = parse_location (uri);
            var key = new KeyFile ();
            key.set_string ("Library", "location", folder.get_uri ());
            if (DirUtils.create_with_parents (Path.get_dirname (path), 0700) != 0)
                throw new IOError.FAILED ("No se pudo crear la carpeta de configuración.");
            FileUtils.set_contents (path, key.to_data ());
        }
    }
}
