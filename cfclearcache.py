import requests
import time

# add api token
api_token = "api token"

# request header
headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer {}".format(api_token),
}

# json data
json_data = {"purge_everything": True}

# counter to keep track of requestss
request_counter = 0

# page number of zones
page = 1

# set up a loop to paginate through the results
while True:
    # request to the Cloudflare API to get a list of zones
    response = requests.get(
        "https://api.cloudflare.com/client/v4/zones",
        headers=headers,
        params={"per_page": 100, "page": page},
    )

    # check the response status code
    if response.status_code == 200:
        # get the list of zones from the response
        zones = response.json()["result"]

        # find zone id
        for zone in zones:
            # Get the zone ID
            zone_id = zone["id"]

            # request to the Cloudflare API to clear the cache for this zone
            response = requests.post(
                "https://api.cloudflare.com/client/v4/zones/{}/purge_cache".format(
                    zone_id
                ),
                headers=headers,
                json=json_data,
            )

            # check the response status code
            if response.status_code == 200:
                print("Cache cleared for zone: {}".format(zone["name"]))
            else:
                print("Error clearing cache for zone: {}".format(zone["name"]))

            # increment the request counter
            request_counter += 1

            # if the requests reached 999, sleep for 310 seconds
            if request_counter == 999:
                print("Sleeping for 310 seconds...")
                time.sleep(310)
                request_counter = 0

        # increment the page number
        page += 1
    else:
        print("Error getting list of zones")
        break
