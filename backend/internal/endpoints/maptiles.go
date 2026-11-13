package endpoints

import (
	"io"
	"log"
	"net/http"
	"strconv"
	"time"
)

// **the admin panel cannot fetch a tile itself.** Every request it makes carries no `Referer` —
// webui sets `Referrer-Policy: same-origin` — and tile.openstreetmap.org answers those with its
// "app is not following the tile usage policy" image, which is what the picker used to draw. Their
// policy asks for a User-Agent naming the application and a way to reach whoever runs it; a server
// can send that and a browser cannot be made to. The keyless alternatives were weighed and lost:
// CARTO's basemaps now want an API key, and Esri's streets of Tashkent are blank.
const (
	tileUpstream  = "https://tile.openstreetmap.org/"
	tileUserAgent = "domix-admin/1.0 (+https://domix-app.uz; domix.support@gmail.com)"

	tileMinZoom = 3
	tileMaxZoom = 19
	// a 256px OSM tile is tens of kilobytes; this is the ceiling on what an upstream answer may
	// spend of this process's memory, not a size anything real approaches
	tileMaxBytes = 1 << 20
)

// its own client: the default has no timeout at all, and a tile server that stops answering would
// otherwise hold a goroutine and the admin's rate-limit budget for as long as the socket lives.
var tileClient = &http.Client{Timeout: 10 * time.Second}

// MapTile proxies one raster tile to the shop editor's map picker.
//
// **this route is behind RequireAdmin like every other, and must stay there.** Open to the
// internet it would be a free OpenStreetMap proxy under our address, and the first thing that
// happens to one of those is that OSM blocks the server that runs it.
func (a *Admin) MapTile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		writeAPIError(w, http.StatusMethodNotAllowed, "method_not_allowed", "use GET")
		return
	}

	z, err := strconv.Atoi(r.PathValue("z"))
	if err != nil || z < tileMinZoom || z > tileMaxZoom {
		writeAPIError(w, http.StatusBadRequest, "invalid_tile", "no such tile")
		return
	}
	// the bound is what stops a path element reaching the upstream url as anything but a number
	side := 1 << z
	x, errX := strconv.Atoi(r.PathValue("x"))
	y, errY := strconv.Atoi(r.PathValue("y"))
	if errX != nil || errY != nil || x < 0 || x >= side || y < 0 || y >= side {
		writeAPIError(w, http.StatusBadRequest, "invalid_tile", "no such tile")
		return
	}

	url := tileUpstream + strconv.Itoa(z) + "/" + strconv.Itoa(x) + "/" + strconv.Itoa(y) + ".png"
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, url, nil)
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "server_error", "could not ask for the tile")
		return
	}
	req.Header.Set("User-Agent", tileUserAgent)

	res, err := tileClient.Do(req)
	if err != nil {
		log.Printf("map tile %d/%d/%d: %v", z, x, y, err)
		writeAPIError(w, http.StatusBadGateway, "tile_unavailable", "the map is not answering")
		return
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		log.Printf("map tile %d/%d/%d: upstream said %d", z, x, y, res.StatusCode)
		writeAPIError(w, http.StatusBadGateway, "tile_unavailable", "the map is not answering")
		return
	}

	w.Header().Set("Content-Type", "image/png")
	// **the cache is the panel's, and it is the half of the policy we owe.** A week of browser cache
	// is what keeps a founder panning around Tashkent from asking the volunteer servers for the same
	// tile twice; `private`, because the answer went through an admin's token.
	w.Header().Set("Cache-Control", "private, max-age=604800")
	if _, err := io.Copy(w, io.LimitReader(res.Body, tileMaxBytes)); err != nil {
		log.Printf("map tile %d/%d/%d: %v", z, x, y, err)
	}
}
