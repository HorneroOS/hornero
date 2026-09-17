module hornero_core

import net.http
import os
import time
import x.json2

// Native weather backend: mirrors the retired dots-weather-info legacy
// body. Field reads serve the ~/.cache/dots/weather files directly
// (no API key needed); --getdata serves a fresh cache or refreshes it
// from ip-api.com + OpenWeatherMap with a 10-minute TTL.
// Seams (hermetic tests): HORNERO_WEATHER_CACHE_DIR,
// HORNERO_WEATHER_GEO_URL, HORNERO_WEATHER_API_URL. The API key comes
// from WEATHER_API_KEY or $XDG_CONFIG_HOME/credentials/weather_api_key.

const weather_cache_ttl = 600

struct WeatherMood {
	icon  string
	quote string
	hex   string
}

// weather_mood maps an OpenWeatherMap icon code to its glyph, quote,
// and hex color — the dots-weather-info doom-if table, verbatim.
fn weather_mood(code string) WeatherMood {
	match code {
		'50d' {
			return WeatherMood{
				icon:  '󰖑'
				quote: "Forecast says it's misty \nMake sure you don't get lost on your way..."
				hex:   '#84afdb'
			}
		}
		'50n' {
			return WeatherMood{
				icon:  '󰖑'
				quote: "Forecast says it's a misty night \nDon't go anywhere tonight or you might get lost..."
				hex:   '#84afdb'
			}
		}
		'01d' {
			return WeatherMood{
				icon:  '󰖙'
				quote: "It's a sunny day, gonna be fun! \nDon't go wandering all by yourself though..."
				hex:   '#ffd86b'
			}
		}
		'01n' {
			return WeatherMood{
				icon:  '󰖔'
				quote: "It's a clear night \nYou might want to take a evening stroll to relax..."
				hex:   '#fcdcf6'
			}
		}
		'02d' {
			return WeatherMood{
				icon:  '󰖕'
				quote: "It's  cloudy, sort of gloomy \nYou'd better get a book to read..."
				hex:   '#adadff'
			}
		}
		'02n' {
			return WeatherMood{
				icon:  '󰼱'
				quote: "It's a cloudy night \nHow about some hot chocolate and a warm bed?"
				hex:   '#adadff'
			}
		}
		'03d' {
			return WeatherMood{
				icon:  '󰖐'
				quote: "It's  cloudy, sort of gloomy \nYou'd better get a book to read..."
				hex:   '#adadff'
			}
		}
		'03n' {
			return WeatherMood{
				icon:  '󰖐'
				quote: "It's a cloudy night \nHow about some hot chocolate and a warm bed?"
				hex:   '#adadff'
			}
		}
		'04d' {
			return WeatherMood{
				icon:  '󰖐'
				quote: "It's  cloudy, sort of gloomy \nYou'd better get a book to read..."
				hex:   '#adadff'
			}
		}
		'04n' {
			return WeatherMood{
				icon:  '󰖐'
				quote: "It's a cloudy night \nHow about some hot chocolate and a warm bed?"
				hex:   '#adadff'
			}
		}
		'09d' {
			return WeatherMood{
				icon:  '󰼳'
				quote: "It's rainy, it's a great day! \nGet some ramen and watch as the rain falls..."
				hex:   '#6b95ff'
			}
		}
		'09n' {
			return WeatherMood{
				icon:  '󰖗'
				quote: " It's gonna rain tonight it seems \nMake sure your clothes aren't still outside..."
				hex:   '#6b95ff'
			}
		}
		'10d' {
			return WeatherMood{
				icon:  '󰼳'
				quote: "It's rainy, it's a great day! \nGet some ramen and watch as the rain falls..."
				hex:   '#6b95ff'
			}
		}
		'10n' {
			return WeatherMood{
				icon:  '󰖗'
				quote: " It's gonna rain tonight it seems \nMake sure your clothes aren't still outside..."
				hex:   '#6b95ff'
			}
		}
		'11d' {
			return WeatherMood{
				icon:  ''
				quote: "There's storm for forecast today \nMake sure you don't get blown away..."
				hex:   '#ffeb57'
			}
		}
		'11n' {
			return WeatherMood{
				icon:  ''
				quote: "There's gonna be storms tonight \nMake sure you're warm in bed and the windows are shut..."
				hex:   '#ffeb57'
			}
		}
		'13d' {
			return WeatherMood{
				icon:  ''
				quote: "It's gonna snow today \nYou'd better wear thick clothes and make a snowman as well!"
				hex:   '#e3e6fc'
			}
		}
		'13n' {
			return WeatherMood{
				icon:  ''
				quote: "It's gonna snow tonight \nMake sure you get up early tomorrow to see the sights..."
				hex:   '#e3e6fc'
			}
		}
		'40d' {
			return WeatherMood{
				icon:  '󰖑'
				quote: "Forecast says it's misty \nMake sure you don't get lost on your way..."
				hex:   '#84afdb'
			}
		}
		'40n' {
			return WeatherMood{
				icon:  '󰖑'
				quote: "Sort of odd, I don't know what to forecast \nMake sure you have a good time!"
				hex:   '#adadff'
			}
		}
		else {
			return WeatherMood{
				icon:  '󰖑'
				quote: "Sort of odd, I don't know what to forecast \nMake sure you have a good time!"
				hex:   '#adadff'
			}
		}
	}
}

// weather_cache_dir resolves the weather cache root.
pub fn weather_cache_dir() string {
	env := os.getenv('HORNERO_WEATHER_CACHE_DIR')
	if env.len > 0 {
		return env
	}
	return os.join_path(os.home_dir(), '.cache', 'dots', 'weather')
}

// weather_api_key resolves the OpenWeatherMap key: env first, then the
// credentials file (XDG-aware, like the script).
fn weather_api_key() string {
	key := os.getenv('WEATHER_API_KEY')
	if key.len > 0 {
		return key
	}
	cfg := os.getenv('XDG_CONFIG_HOME')
	base := if cfg.len > 0 { cfg } else { os.join_path(os.home_dir(), '.config') }
	raw := os.read_file(os.join_path(base, 'credentials', 'weather_api_key')) or { '' }
	return raw.trim_space()
}

fn weather_geo_url() string {
	env := os.getenv('HORNERO_WEATHER_GEO_URL')
	if env.len > 0 {
		return env
	}
	return 'http://ip-api.com/json/'
}

fn weather_api_url() string {
	env := os.getenv('HORNERO_WEATHER_API_URL')
	if env.len > 0 {
		return env
	}
	return 'http://api.openweathermap.org/data/2.5/weather'
}

// weather_cache_valid mirrors is_cache_valid: timestamp + raw exist,
// raw non-empty, age under TTL.
fn weather_cache_valid(dir string) bool {
	ts_raw := os.read_file(os.join_path(dir, 'weather-timestamp')) or { return false }
	raw := os.read_file(os.join_path(dir, 'weather-raw')) or { return false }
	if raw.trim_space().len == 0 {
		return false
	}
	ts := ts_raw.trim_space().int()
	return time.now().unix() - ts < weather_cache_ttl
}

fn weather_write_cache(dir string, name string, content string) {
	os.write_file(os.join_path(dir, name), content) or {}
}

// weather_write_unavailable stores the "Weather Unavailable" set the
// widgets consume when a fetch fails.
fn weather_write_unavailable(dir string) {
	weather_write_cache(dir, 'weather-stat', 'Weather Unavailable')
	weather_write_cache(dir, 'weather-icon', ' ')
	weather_write_cache(dir, 'weather-quote', "Ah well, no weather huh? \nEven if there's no weather, it's gonna be a great day!")
	weather_write_cache(dir, 'weather-degree', '-')
	weather_write_cache(dir, 'weather-hex', '#adadff')
}

// weather_title_case capitalizes every word, like the script's sed.
fn weather_title_case(s string) string {
	words := s.split(' ')
	mut out := []string{}
	for w in words {
		if w.len == 0 {
			out << w
			continue
		}
		out << w[0].ascii_str().to_upper() + w[1..]
	}
	return out.join(' ')
}

// weather_json_str reads one string field from a decoded object.
fn weather_json_str(m map[string]json2.Any, key string) string {
	if key !in m {
		return ''
	}
	v := m[key] or { return '' }
	return v.str()
}

// weather_http_get fetches one URL: file:// URLs (query stripped)
// read straight from disk so tests stay hermetic with fixture JSON;
// anything else goes through net.http.
fn weather_http_get(url string) !string {
	if url.starts_with('file://') {
		path := url[7..].split('?')[0]
		return os.read_file(path)!
	}
	resp := http.get(url)!
	return resp.body
}

// weather_fetch runs the geo + OpenWeatherMap refresh and rewrites the
// cache files, returning the raw JSON (the --getdata contract).
fn weather_fetch(dir string, key string) !string {
	geo_body := weather_http_get(weather_geo_url())!
	geo := json2.decode[json2.Any](geo_body)!
	gm := geo as map[string]json2.Any
	lat := weather_json_str(gm, 'lat')
	lon := weather_json_str(gm, 'lon')
	city := weather_json_str(gm, 'city')
	region := weather_json_str(gm, 'regionName')
	country := weather_json_str(gm, 'country')
	weather_write_cache(dir, 'weather-location', '${city}, ${region}, ${country}')
	url := '${weather_api_url()}?APPID=${key}&lat=${lat}&lon=${lon}&units=metric'
	raw := weather_http_get(url)!
	if raw.trim_space().len == 0 {
		weather_write_unavailable(dir)
		return error('empty weather response')
	}
	weather_write_cache(dir, 'weather-raw', raw)
	weather_write_cache(dir, 'weather-timestamp', time.now().unix().str())
	doc := json2.decode[json2.Any](raw)!
	dm := doc as map[string]json2.Any
	main := (dm['main'] or { json2.Any('') }).as_map()
	temp := (main['temp'] or { json2.Any(0.0) }).f64().str().split('.')[0]
	arr := (dm['weather'] or { json2.Any('') }).as_array()
	mut code := ''
	mut desc := ''
	if arr.len > 0 {
		first := arr[0].as_map()
		code = weather_json_str(first, 'icon')
		desc = weather_title_case(weather_json_str(first, 'description'))
	}
	mood := weather_mood(code)
	weather_write_cache(dir, 'weather-icon', mood.icon)
	weather_write_cache(dir, 'weather-stat', desc)
	weather_write_cache(dir, 'weather-degree', temp + '°C')
	weather_write_cache(dir, 'weather-quote', mood.quote)
	weather_write_cache(dir, 'weather-hex', mood.hex)
	return raw
}

// weather_getdata_native implements `apps weather --getdata`: fresh
// cache is served without a key; stale cache refreshes (needs a key).
fn weather_getdata_native() CommandResult {
	name := 'apps weather --getdata'
	dir := weather_cache_dir()
	os.mkdir_all(dir) or {}
	if weather_cache_valid(dir) {
		raw := os.read_file(os.join_path(dir, 'weather-raw')) or { '' }
		return ok_result(name, raw, {
			'field': 'getdata'
		})
	}
	key := weather_api_key()
	if key.len == 0 {
		return fail_result(name, "Error: Weather API key not found. Set WEATHER_API_KEY environment variable or configure LastPass entry 'weather_api_key'.")
	}
	raw := weather_fetch(dir, key) or {
		return fail_result(name, 'weather refresh failed: ${err.msg()}')
	}
	return ok_result(name, raw, {
		'field': 'getdata'
	})
}

// weather_field_native implements the cache-file reads: --icon,
// --temp, --hex, --stat, --loc, --quote (first line), --quote2 (last).
fn weather_field_native(field string) CommandResult {
	name := 'apps weather --${field}'
	dir := weather_cache_dir()
	file := if field == 'loc' {
		'weather-location'
	} else if field == 'quote' || field == 'quote2' {
		'weather-quote'
	} else if field == 'temp' {
		'weather-degree'
	} else if field == 'stat' {
		'weather-stat'
	} else if field == 'hex' {
		'weather-hex'
	} else {
		'weather-icon'
	}
	content := os.read_file(os.join_path(dir, file)) or { '' }
	if field == 'quote' {
		return ok_result(name, content.split_into_lines()[0], {
			'field': field
		})
	}
	if field == 'quote2' {
		lines := content.split_into_lines()
		return ok_result(name, lines[lines.len - 1], {
			'field': field
		})
	}
	return ok_result(name, content, {
		'field': field
	})
}
