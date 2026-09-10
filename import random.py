import random
import string
import requests

def get_random_url():
    # Generates a random 6-letter string (e.g., "abxztq")
    letters = ''.join(random.choices(string.ascii_lowercase, k=6))
    # Note: Randomly guessing domains yields a very high failure rate. 
    # Real scanners usually read from a wordlist or a list of registered domains.
    return f"https://www.{letters}.com"

def scan_url(url):
    try:
        # timeout=2 prevents the script from hanging on dead servers
        response = requests.get(url, timeout=2)
        if response.status_code == 200:
            print(f"[FOUND] {url} returned Status 200")
    except requests.exceptions.RequestException:
        # Silently ignore connection errors, timeouts, and NXDOMAINs
        pass

# Example of running a quick test check
target = "https://google.com" # Example test target
scan_url(target)
