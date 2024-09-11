package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"net/url"
)

// Bird Struct used to store and transmit data
type Bird struct {
	Name        string
	Description string
	Image       string
}

// Function that return a default Bird when an error occurs
func defaultBird(err error) Bird {
	return Bird{
		Name:        "Bird in disguise",
		Description: fmt.Sprintf("This bird is in disguise because: %s", err),
		Image:       "https://www.pokemonmillennium.net/wp-content/uploads/2015/11/missingno.png",
	}
}

// Function that makes request to second API ( running on port 4200)
// uses `url.QueryEscape` for safe encoding of Bird name
func getBirdImage(birdName string) (string, error) {
	res, err := http.Get(fmt.Sprintf("http://localhost:4200?birdName=%s", url.QueryEscape(birdName)))
	if err != nil {
		return "", err
	}
	body, err := io.ReadAll(res.Body)
	return string(body), err
}

// Function that fetches a random bird factoid from an external API
// And then call `getBirdImage`to get an image for that bird
func getBirdFactoid() Bird {
	res, err := http.Get(fmt.Sprintf("%s%d", "https://freetestapi.com/api/v1/birds/", rand.IntN(50)))
	if err != nil {
		fmt.Printf("Error reading bird API: %s\n", err)
		return defaultBird(err)
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		fmt.Printf("Error parsing bird API response: %s\n", err)
		return defaultBird(err)
	}
	var bird Bird
	err = json.Unmarshal(body, &bird)
	if err != nil {
		fmt.Printf("Error unmarshalling bird: %s", err)
		return defaultBird(err)
	}
	birdImage, err := getBirdImage(bird.Name)
	if err != nil {
		fmt.Printf("Error in getting bird image: %s\n", err)
		return defaultBird(err)
	}
	bird.Image = birdImage
	return bird
}

// The main Hundler function for the API. It gets a bird factoid and
// write it as JSON Response
func bird(w http.ResponseWriter, r *http.Request) {
	var buffer bytes.Buffer
	json.NewEncoder(&buffer).Encode(getBirdFactoid())
	io.WriteString(w, buffer.String())
}

// Main function that Sets a HTTP server, listening on port 4201
func main() {
	http.HandleFunc("/", bird)
	http.ListenAndServe(":4201", nil)
}
