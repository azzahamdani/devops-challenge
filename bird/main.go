package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand/v2"
	"net/http"
	"net/url"
)

type Bird struct {
	Name        string
	Description string
	Image       string
}

func defaultBird(err error) Bird {
	return Bird{
		Name:        "Bird in disguise",
		Description: fmt.Sprintf("This bird is in disguise because: %s", err),
		Image:       "https://www.pokemonmillennium.net/wp-content/uploads/2015/11/missingno.png",
	}
}

func getBirdImage(birdName string) (string, error) {
	url := fmt.Sprintf("http://localhost:4200?birdName=%s", url.QueryEscape(birdName))
	log.Printf("INFO: GET %s", url)
	res, err := http.Get(url)
	if err != nil {
		return "", err
	}
	body, err := io.ReadAll(res.Body)
	return string(body), err
}

func getBirdFactoid() Bird {
	url := fmt.Sprintf("%s%d", "https://freetestapi.com/api/v1/birds/", rand.IntN(50))
	log.Printf("INFO: GET %s", url)
	res, err := http.Get(url)
	if err != nil {
		log.Printf("ERROR: Failed to fetch bird factoid: %s", err)
		return defaultBird(err)
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		log.Printf("ERROR: Failed to read response body: %s", err)
		return defaultBird(err)
	}
	var bird Bird
	err = json.Unmarshal(body, &bird)
	if err != nil {
		log.Printf("ERROR: Failed to unmarshal bird data: %s", err)
		return defaultBird(err)
	}
	birdImage, err := getBirdImage(bird.Name)
	if err != nil {
		log.Printf("ERROR: Failed to get bird image: %s", err)
		return defaultBird(err)
	}
	bird.Image = birdImage
	return bird
}

func bird(w http.ResponseWriter, r *http.Request) {
	log.Printf("INFO: %s %s", r.Method, r.URL.Path)
	var buffer bytes.Buffer
	json.NewEncoder(&buffer).Encode(getBirdFactoid())
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
	log.Println("INFO: Starting server on :4201")
	if err := http.ListenAndServe(":4201", nil); err != nil {
		log.Fatalf("ERROR: Failed to start server: %v", err)
	}
}
