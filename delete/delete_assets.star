load('http', http_get='get', http_delete='delete', 'url_encode')
load('json', json_encode='encode', json_decode='decode')

def main(*args, **kwargs):
    """
    Deletes assets from runZero based on a search query.
    """
    org_token = kwargs.get('access_secret')

    base_url = "https://console.runzero.com/api/v1.0"
    search_url = "{}/export/org/assets.json".format(base_url)
    delete_url = "{}/org/assets/bulk/delete".format(base_url)

    query = "type:mobile and not source:runZero"

    headers = {
        "Authorization": "Bearer {}".format(org_token)
    }

    search_response = http_get(search_url, headers=headers, params={"search": query, "fields": "id"})
    if search_response.status_code != 200:
        print("Failed to retrieve asset list, status: {}".format(search_response.status_code))
        return []

    assets_data = json_decode(search_response.body)
    asset_ids = [x['id'] for x in assets_data]

    if len(asset_ids) > 0:
        payload = json_encode({"asset_ids": asset_ids})
        delete_response = http_delete(delete_url, headers=headers, body=bytes(payload))
        if delete_response.status_code == 204:
            print("Deleted all matching assets")
        else:
            print("Failed to delete assets, status: {}".format(delete_response.status_code))
    else:
        print("No assets matched the query")

    return []