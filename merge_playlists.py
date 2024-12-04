import requests

# URLs of the M3U playlists
url1 = "https://bit.ly/tta-m3u"
url2 = "https://tinyurl.com/multiservice21?region=us&service=PlutoTv"

# Output file name
output_file = "merged_playlist.m3u"

def merge_playlists():
    try:
        # Fetch both playlists
        response1 = requests.get(url1)
        response2 = requests.get(url2)

        # Check if both requests were successful
        if response1.status_code == 200 and response2.status_code == 200:
            # Combine the playlists
            combined_playlist = response1.text + "\n" + response2.text

            # Save the combined playlist to a file
            with open(output_file, "w", encoding="utf-8") as file:
                file.write(combined_playlist)

            print(f"Merged playlist saved to {output_file}.")
        else:
            print(f"Failed to fetch one or both playlists. Status codes: {response1.status_code}, {response2.status_code}")
    except Exception as e:
        print(f"An error occurred: {e}")

# Run the function
merge_playlists()
