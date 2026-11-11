using Music;

// Only this controlled loopback origin may bypass the production Wikimedia HTTPS policy.
class PublicPhotoFixture : Object {
    public Soup.Server server = new Soup.Server ("server-header", "artist-photo-fixture", null);
    public string origin;
    public Bytes jpeg = new Bytes (Base64.decode (
        "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABwEBAQAAAAAAAAAAAAAAAAAABQcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAQABADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCOAL+Kf//Z"));

    public PublicPhotoFixture (bool canonical_file_title = false,
                               string license_name = "CC BY-SA 4.0",
                               string license_url = "https://creativecommons.org/licenses/by-sa/4.0/") throws Error {
        string filename = canonical_file_title ? "Artist_portrait.jpg" : "Portrait.jpg";
        string commons_title = canonical_file_title ? "File:Artist portrait.jpg" : "File:Portrait.jpg";
        server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
        string uri = server.get_uris ().data.to_string ();
        origin = uri.substring (0, uri.length - 1);
        server.add_handler (null, (server, message, path, query) => {
            string body;
            switch (path) {
            case "/api/rest_v1/page/summary/Nina Simone":
                body = """{"type":"standard","title":"Nina Simone","description":"American singer and pianist","thumbnail":{"source":"%s/portrait.jpg","width":16,"height":16},"originalimage":{"source":"%s/original/%s","width":640,"height":640}}""".printf (origin, origin, filename);
                break;
            case "/w/api.php":
                // Soup has already decoded the query parameters, including the file title.
                if (canonical_file_title && (query == null || query.lookup ("titles") != "File:" + filename)) {
                    message.set_status (400, null);
                    return;
                }
                body = """{"query":{"pages":{"123":{"pageid":123,"ns":6,"title":"%s","imageinfo":[{"url":"%s/original/%s","thumburl":"%s/portrait.jpg","descriptionurl":"%s/wiki/File:%s","extmetadata":{"Artist":{"value":"<a href=\"https://example.org/photographer\">Example Photographer</a>"},"LicenseShortName":{"value":"%s"},"LicenseUrl":{"value":"%s"}}}]}}}}""".printf (commons_title, origin, filename, origin, origin, filename, license_name, license_url);
                break;
            case "/portrait.jpg":
                message.set_status (200, null);
                message.set_response ("image/jpeg", Soup.MemoryUse.COPY, jpeg.get_data ());
                return;
            default:
                message.set_status (404, null);
                return;
            }
            message.set_status (200, null);
            message.set_response ("application/json", Soup.MemoryUse.COPY, body.data);
        });
    }
}

void givenPublicArtistPortrait_whenFetched_thenReturnsPhotoBytesAndAttribution () {
    try {
        var fixture = new PublicPhotoFixture ();
        var photos = new ArtistPhotos.for_test_server (fixture.origin);
        var loop = new MainLoop ();
        uint deadline = Timeout.add_seconds (5, () => {
            error ("La consulta local de retrato no terminó en cinco segundos");
        });
        photos.fetch.begin ("Nina Simone", new Cancellable (), (obj, result) => {
            try {
                var photo = photos.fetch.end (result);
                assert_nonnull (photo);
                assert (photo.bytes.compare (fixture.jpeg) == 0);
                assert_cmpstr (photo.author, CompareOperator.EQ, "Example Photographer");
                assert_cmpstr (photo.license_name, CompareOperator.EQ, "CC BY-SA 4.0");
                assert_cmpstr (photo.license_url, CompareOperator.EQ,
                               "https://creativecommons.org/licenses/by-sa/4.0/");
                assert_cmpstr (photo.source_url, CompareOperator.EQ,
                               fixture.origin + "/wiki/File:Portrait.jpg");
            } catch (Error e) { error ("Retrato público: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        Source.remove (deadline);
        fixture.server.disconnect ();
    } catch (Error e) { error ("Fixture de retrato: %s", e.message); }
}

void givenWikimediaCanonicalFileTitle_whenPortraitFetched_thenReturnsAttributedPhoto () {
    try {
        var fixture = new PublicPhotoFixture (true);
        var photos = new ArtistPhotos.for_test_server (fixture.origin);
        var loop = new MainLoop ();
        uint deadline = Timeout.add_seconds (5, () => {
            error ("La consulta local de retrato canónico no terminó en cinco segundos");
        });
        photos.fetch.begin ("Nina Simone", new Cancellable (), (obj, result) => {
            try {
                var photo = photos.fetch.end (result);
                assert_nonnull (photo);
                assert (photo.bytes.compare (fixture.jpeg) == 0);
                assert_cmpstr (photo.author, CompareOperator.EQ, "Example Photographer");
                assert_cmpstr (photo.license_name, CompareOperator.EQ, "CC BY-SA 4.0");
                assert_cmpstr (photo.license_url, CompareOperator.EQ,
                               "https://creativecommons.org/licenses/by-sa/4.0/");
                assert_cmpstr (photo.source_url, CompareOperator.EQ,
                               fixture.origin + "/wiki/File:Artist_portrait.jpg");
            } catch (Error e) { error ("Retrato con título canónico: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        Source.remove (deadline);
        fixture.server.disconnect ();
    } catch (Error e) { error ("Fixture de retrato canónico: %s", e.message); }
}

void givenCommonsLicenseWithoutTrailingSlash_whenPortraitFetched_thenReturnsPhotoWithOriginalLicenseUrl () {
    try {
        string original_license_url = "https://creativecommons.org/licenses/by/3.0";
        var fixture = new PublicPhotoFixture (false, "CC BY 3.0", original_license_url);
        var photos = new ArtistPhotos.for_test_server (fixture.origin);
        var loop = new MainLoop ();
        uint deadline = Timeout.add_seconds (5, () => {
            error ("La consulta local de retrato con licencia sin barra no terminó en cinco segundos");
        });
        photos.fetch.begin ("Nina Simone", new Cancellable (), (obj, result) => {
            try {
                var photo = photos.fetch.end (result);
                assert_nonnull (photo);
                assert_cmpstr (photo.license_url, CompareOperator.EQ, original_license_url);
                assert_cmpstr (photo.license_name, CompareOperator.EQ, "CC BY 3.0");
                assert_cmpstr (photo.author, CompareOperator.EQ, "Example Photographer");
                assert_cmpstr (photo.source_url, CompareOperator.EQ,
                               fixture.origin + "/wiki/File:Portrait.jpg");
                assert (photo.bytes.compare (fixture.jpeg) == 0);
            } catch (Error e) { error ("Retrato con licencia sin barra: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        Source.remove (deadline);
        fixture.server.disconnect ();
    } catch (Error e) { error ("Fixture de licencia sin barra: %s", e.message); }
}

void givenCommonsLocalizedLicense_whenPortraitFetched_thenPreservesJurisdictionAndAttribution () {
    try {
        string original_license_name = "CC BY-SA 2.0 fr";
        string original_license_url = "https://creativecommons.org/licenses/by-sa/2.0/fr/deed.en";
        var fixture = new PublicPhotoFixture (false, original_license_name, original_license_url);
        var photos = new ArtistPhotos.for_test_server (fixture.origin);
        var loop = new MainLoop ();
        uint deadline = Timeout.add_seconds (5, () => {
            error ("La consulta local de retrato con licencia localizada no terminó en cinco segundos");
        });
        photos.fetch.begin ("Nina Simone", new Cancellable (), (obj, result) => {
            try {
                var photo = photos.fetch.end (result);
                assert_nonnull (photo);
                assert_cmpstr (photo.license_url, CompareOperator.EQ, original_license_url);
                assert_cmpstr (photo.license_name, CompareOperator.EQ, original_license_name);
                assert_cmpstr (photo.author, CompareOperator.EQ, "Example Photographer");
                assert_cmpstr (photo.source_url, CompareOperator.EQ,
                               fixture.origin + "/wiki/File:Portrait.jpg");
                assert (photo.bytes.compare (fixture.jpeg) == 0);
            } catch (Error e) { error ("Retrato con licencia localizada: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        Source.remove (deadline);
        fixture.server.disconnect ();
    } catch (Error e) { error ("Fixture de licencia localizada: %s", e.message); }
}

void givenPortraitResponseRedirectsOutsideWikimedia_whenFetched_thenRejectsWithoutPhoto () {
    try {
        var fixture = new PublicPhotoFixture ();
        fixture.server.add_handler ("/portrait.jpg", (server, message, path, query) => {
            message.set_status (302, null);
            message.get_response_headers ().replace ("Location", "http://example.invalid/portrait.jpg");
        });
        var photos = new ArtistPhotos.for_test_server (fixture.origin);
        var loop = new MainLoop ();
        ArtistPhoto? photo = null;
        Error? failure = null;
        uint deadline = Timeout.add_seconds (5, () => {
            error ("La consulta local de retrato redirigido no terminó en cinco segundos");
        });
        photos.fetch.begin ("Nina Simone", new Cancellable (), (obj, result) => {
            try {
                photo = photos.fetch.end (result);
            } catch (Error e) {
                failure = e;
            }
            loop.quit ();
        });
        loop.run ();
        Source.remove (deadline);
        fixture.server.disconnect ();
        assert (failure != null);
        assert (failure.matches (IOError.quark (), IOError.FAILED));
        assert_cmpstr (failure.message, CompareOperator.EQ, "Respuesta HTTP 302");
        assert_null (photo);
    } catch (Error e) { error ("Fixture de retrato redirigido: %s", e.message); }
}

void givenArtistNameMatchesNonMusicalEntity_whenPortraitFetched_thenReturnsNoPhoto () {
    try {
        var fixture = new PublicPhotoFixture ();
        fixture.server.add_handler ("/api/rest_v1/page/summary/Boston", (server, message, path, query) => {
            string body = """{"type":"standard","title":"Boston","description":"Capital and largest city of Massachusetts, United States","thumbnail":{"source":"%s/portrait.jpg","width":16,"height":16},"originalimage":{"source":"%s/original/Portrait.jpg","width":640,"height":640}}""".printf (fixture.origin, fixture.origin);
            message.set_status (200, null);
            message.set_response ("application/json", Soup.MemoryUse.COPY, body.data);
        });
        var photos = new ArtistPhotos.for_test_server (fixture.origin);
        var loop = new MainLoop ();
        uint deadline = Timeout.add_seconds (5, () => {
            error ("La consulta local de Boston no terminó en cinco segundos");
        });
        photos.fetch.begin ("Boston", new Cancellable (), (obj, result) => {
            try {
                var photo = photos.fetch.end (result);
                assert_null (photo);
            } catch (Error e) { error ("Entidad no musical: %s", e.message); }
            loop.quit ();
        });
        loop.run ();
        Source.remove (deadline);
        fixture.server.disconnect ();
    } catch (Error e) { error ("Fixture de entidad no musical: %s", e.message); }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/artist-photos/givenPublicArtistPortrait_whenFetched_thenReturnsPhotoBytesAndAttribution",
                   givenPublicArtistPortrait_whenFetched_thenReturnsPhotoBytesAndAttribution);
    Test.add_func ("/artist-photos/givenWikimediaCanonicalFileTitle_whenPortraitFetched_thenReturnsAttributedPhoto",
                   givenWikimediaCanonicalFileTitle_whenPortraitFetched_thenReturnsAttributedPhoto);
    Test.add_func ("/artist-photos/givenCommonsLicenseWithoutTrailingSlash_whenPortraitFetched_thenReturnsPhotoWithOriginalLicenseUrl",
                   givenCommonsLicenseWithoutTrailingSlash_whenPortraitFetched_thenReturnsPhotoWithOriginalLicenseUrl);
    Test.add_func ("/artist-photos/givenCommonsLocalizedLicense_whenPortraitFetched_thenPreservesJurisdictionAndAttribution",
                   givenCommonsLocalizedLicense_whenPortraitFetched_thenPreservesJurisdictionAndAttribution);
    Test.add_func ("/artist-photos/givenPortraitResponseRedirectsOutsideWikimedia_whenFetched_thenRejectsWithoutPhoto",
                   givenPortraitResponseRedirectsOutsideWikimedia_whenFetched_thenRejectsWithoutPhoto);
    Test.add_func ("/artist-photos/givenArtistNameMatchesNonMusicalEntity_whenPortraitFetched_thenReturnsNoPhoto",
                   givenArtistNameMatchesNonMusicalEntity_whenPortraitFetched_thenReturnsNoPhoto);
    return Test.run ();
}
