package imagestore

import (
	"strings"
	"testing"
)

// **What is testable about R2 without R2, and why that is the right line.** Everything this package
// does over the network is one library call each - PutObject, RemoveObject, ListObjects - and a test
// for those would be a test of minio-go. What is *ours* is the arithmetic in front of them: which
// environment variables make a configuration, what host they resolve to, and what a stored path looks
// like as a url. Each of those fails in a way that is silent until the first upload in production, and
// each is a pure function.
//
// So there is no mock S3 here and no httptest server pretending to be Cloudflare. A fake that answers
// the way we expect only ever proves we are consistent with ourselves.

func TestR2IsConfiguredByFourVariablesOrNone(t *testing.T) {
	full := map[string]string{
		EnvR2AccountID: "abc123",
		EnvR2AccessKey: "AKIA",
		EnvR2SecretKey: "s3cret",
		EnvR2Bucket:    "domix-photos",
	}

	t.Run("none set is a laptop", func(t *testing.T) {
		for name := range full {
			t.Setenv(name, "")
		}
		cfg, wanted, err := R2ConfigFromEnv()
		if err != nil {
			t.Fatalf("an empty environment is not an error: %v", err)
		}
		if wanted {
			t.Errorf("an empty environment asked for R2: %+v", cfg)
		}
	})

	t.Run("all four is a deployment", func(t *testing.T) {
		for name, value := range full {
			t.Setenv(name, value)
		}
		cfg, wanted, err := R2ConfigFromEnv()
		if err != nil || !wanted {
			t.Fatalf("wanted=%v err=%v, expected a complete configuration", wanted, err)
		}
		if cfg.Bucket != "domix-photos" || cfg.AccessKey != "AKIA" {
			t.Errorf("the values did not survive: %+v", cfg)
		}
	})

	// **the one that matters.** Three of four is somebody halfway through filling in a .env, and the
	// tempting answer - fall back to the disk - gives a server that works perfectly until it is
	// redeployed, at which point every photo uploaded since is gone with the container.
	for missing := range full {
		t.Run("missing "+missing+" is refused, not ignored", func(t *testing.T) {
			for name, value := range full {
				if name == missing {
					t.Setenv(name, "")
					continue
				}
				t.Setenv(name, value)
			}
			_, wanted, err := R2ConfigFromEnv()
			if !wanted {
				t.Fatal("a partly-filled configuration was read as 'no R2 wanted'")
			}
			if err == nil {
				t.Fatal("a partly-filled configuration was accepted")
			}
			if !strings.Contains(err.Error(), missing) {
				t.Errorf("the error does not name %s: %v", missing, err)
			}
		})
	}
}

// The host is derived from the account id rather than configured, so this is the only place the rule
// is written down. Getting it wrong is a DNS failure at the first upload and nowhere earlier.
func TestTheBucketHostIsBuiltFromTheAccountID(t *testing.T) {
	got := R2Config{AccountID: "abc123"}.Endpoint()
	if want := "abc123.r2.cloudflarestorage.com"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
	// minio.New takes a host, not a url - Options.Secure carries the scheme. A scheme here would be
	// signed into the request and rejected as a bad endpoint.
	if strings.Contains(got, "//") {
		t.Errorf("the endpoint carries a scheme: %q", got)
	}
}

func TestTheThumbnailSitsBesideItsMaster(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"uploads/3f/3f9cc1.jpg", "uploads/3f/3f9cc1_thumb.jpg"},
		// the curated catalogue takes the same rule: those files are what most tiles in most grids
		// actually show, so without thumbnails beside them the saving barely happens
		{"universal/001.jpg", "universal/001_thumb.jpg"},
		{"plumbing/058.jpg", "plumbing/058_thumb.jpg"},
	} {
		if got := ThumbPath(tc.in); got != tc.want {
			t.Errorf("ThumbPath(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// **The rule the whole storage split rests on: the database stores a relative path and the host is
// prepended here.** With a full url in the column, moving the photos means rewriting every row and a
// production dump points every tile on a laptop at production.
func TestAStoredPathBecomesAnAddress(t *testing.T) {
	t.Run("unset serves from this api", func(t *testing.T) {
		urls := NewURLs("")
		if urls.Configured() {
			t.Error("an empty IMAGE_BASE_URL reads as configured")
		}
		if got, want := urls.Master("universal/001.jpg"), "/static/products/universal/001.jpg"; got != want {
			t.Errorf("got %q, want %q", got, want)
		}
		if got, want := urls.Thumb("universal/001.jpg"), "/static/products/universal/001_thumb.jpg"; got != want {
			t.Errorf("got %q, want %q", got, want)
		}
	})

	t.Run("set serves from the photo host", func(t *testing.T) {
		// with a trailing slash, because that is how a person types a hostname into a .env and the
		// alternative is every url in the market carrying a double slash
		urls := NewURLs("https://img.domix-api.uz/")
		if !urls.Configured() {
			t.Error("a set IMAGE_BASE_URL reads as unconfigured")
		}
		if got, want := urls.Master("uploads/3f/3f9c.jpg"), "https://img.domix-api.uz/uploads/3f/3f9c.jpg"; got != want {
			t.Errorf("got %q, want %q", got, want)
		}
		if got, want := urls.Thumb("uploads/3f/3f9c.jpg"), "https://img.domix-api.uz/uploads/3f/3f9c_thumb.jpg"; got != want {
			t.Errorf("got %q, want %q", got, want)
		}
	})

	// the zero value is what every struct literal that does not mention photos gets - every test in
	// the endpoints package included - so it has to be the old behaviour rather than an empty host
	t.Run("the zero value is the old behaviour", func(t *testing.T) {
		var urls URLs
		if got, want := urls.Master("universal/001.jpg"), "/static/products/universal/001.jpg"; got != want {
			t.Errorf("got %q, want %q", got, want)
		}
	})
}
