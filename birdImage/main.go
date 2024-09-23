package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
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

func defaultImage() string {
	return "https://www.pokemonmillennium.net/wp-content/uploads/2015/11/missingno.png"
}

func getBirdImage(birdName string) string {
	query := fmt.Sprintf(
		"https://api.unsplash.com/search/photos?page=1&query=%s&client_id=P1p3WPuRfpi7BdnG8xOrGKrRSvU1Puxc1aueUWeQVAI&per_page=1",
		url.QueryEscape(birdName),
	)
	log.Printf("INFO: GET %s", query)
	res, err := http.Get(query)
	if err != nil {
		log.Printf("ERROR: Failed to fetch image: %s", err)
		return defaultImage()
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		log.Printf("ERROR: Failed to read response body: %s", err)
		return defaultImage()
	}
	var response ImageResponse
	err = json.Unmarshal(body, &response)
	if err != nil {
		log.Printf("ERROR: Failed to unmarshal image data: %s", err)
		return defaultImage()
	}
	if len(response.Results) == 0 {
		log.Printf("ERROR: No results found for bird: %s", birdName)
		return defaultImage()
	}
	return response.Results[0].Urls.Thumb
}

func bird(w http.ResponseWriter, r *http.Request) {
	log.Printf("INFO: %s %s", r.Method, r.URL.Path)
	var buffer bytes.Buffer
	birdName := r.URL.Query().Get("birdName")
	if birdName == "" {
		json.NewEncoder(&buffer).Encode(defaultImage())
	} else {
		json.NewEncoder(&buffer).Encode(getBirdImage(birdName))
	}
	io.WriteString(w, buffer.String())
}

func healthCheck(w http.ResponseWriter, r *http.Request) {
	log.Printf("INFO: %s %s", r.Method, r.URL.Path)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func main() {
	http.HandleFunc("/", bird)
	http.HandleFunc("/health", healthCheck)
	log.Println("INFO: Starting server on :4200")
	if err := http.ListenAndServe(":4200", nil); err != nil {
		log.Fatalf("ERROR: Failed to start server: %v", err)
	}
}
