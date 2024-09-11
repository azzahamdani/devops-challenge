package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
)

type Urls struct {
	Thumb string
}

type Links struct {
	Urls Urls
}

type ImageResponse struct {
	Results []Links
}

type Bird struct {
	Image string
}

// Function that return a default string when an error occurs
func defaultImage() string {
	return "https://www.pokemonmillennium.net/wp-content/uploads/2015/11/missingno.png"
}

// Function that queries the Unsplash API to get an image for the given bird name
func getBirdImage(birdName string) string {
	var query = fmt.Sprintf(
		"https://api.unsplash.com/search/photos?page=1&query=%s&client_id=P1p3WPuRfpi7BdnG8xOrGKrRSvU1Puxc1aueUWeQVAI&per_page=1",
		url.QueryEscape(birdName),
	)
	res, err := http.Get(query)
	if err != nil {
		fmt.Printf("Error reading image API: %s\n", err)
		return defaultImage()
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		fmt.Printf("Error parsing image API response: %s\n", err)
		return defaultImage()
	}
	var response ImageResponse
	err = json.Unmarshal(body, &response)
	if err != nil {
		fmt.Printf("Error unmarshalling bird image: %s", err)
		return defaultImage()
	}
	return response.Results[0].Urls.Thumb
}

// This is the main handler for the second API.
// It checks for a birdName query parameter and either returns a default image or calls `getBirdImage“ accordingly.
func bird(w http.ResponseWriter, r *http.Request) {
	var buffer bytes.Buffer
	birdName := r.URL.Query().Get("birdName")
	if birdName == "" {
		json.NewEncoder(&buffer).Encode(defaultImage())
	} else {
		json.NewEncoder(&buffer).Encode(getBirdImage(birdName))
	}
	io.WriteString(w, buffer.String())
}

// Sets up the HTTP server for the second API, listening on port 4200.
func main() {
	http.HandleFunc("/", bird)
	http.ListenAndServe(":4200", nil)
}
