package endpoints

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// the three path elements are pasted into the upstream url, so the bound on them is the whole
// reason nothing else can be. a refused tile must never have reached the network.
func TestATileOutsideTheWorldIsRefusedBeforeAnyRequest(t *testing.T) {
	admin := &Admin{}

	for _, c := range []struct{ name, z, x, y string }{
		{"zoom below the minimum", "1", "0", "0"},
		{"zoom above the maximum", "20", "0", "0"},
		{"zoom is not a number", "../..", "0", "0"},
		{"x past the edge of the world", "3", "8", "0"},
		{"y past the edge of the world", "3", "0", "8"},
		{"a negative column", "3", "-1", "0"},
		{"a path element rather than a number", "3", "0", "0/../../secret"},
	} {
		t.Run(c.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/admin/map/"+c.z+"/"+c.x+"/"+c.y, nil)
			req.SetPathValue("z", c.z)
			req.SetPathValue("x", c.x)
			req.SetPathValue("y", c.y)
			rec := httptest.NewRecorder()

			admin.MapTile(rec, req)

			if rec.Code != http.StatusBadRequest {
				t.Fatalf("answered %d, want 400", rec.Code)
			}
		})
	}
}
