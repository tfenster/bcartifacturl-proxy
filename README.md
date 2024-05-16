# bcartifacturl-proxy

Proxy for artifact URLs read by bccontainerhelper. You can run this on your own environment with the docker image tobiasfenster/bcaup or you can use the publicly available Azure Function https://bca-url-proxy.azurewebsites.net/bca-url/ e.g. like this: https://bca-url-proxy.azurewebsites.net/bca-url/sandbox/de/19


### Examples

| Get-BCArtifactUrl | Url |
| :-- | :-- |
| ```Get-BCArtifactUrl -type Sandbox``` | `https://bca-url-proxy.azurewebsites.net/bca-url/sandbox` |
| ```Get-BCArtifactUrl -select NextMajor -accept_insiderEula``` | `https://bca-url-proxy.azurewebsites.net/bca-url?select=nextmajor&accept_insiderEula` |

### Caching
When a call comes in, it first checks a cache to find out if that artifact URLs has previously been requested. If a valid entry is found, the URL from the cache is returned. If no valid entry is found, `Get-BcArtifactUrl` is called with the supplied parameters and the resulting URL is either returned as redirect or as text content the `DoNotRedirect=true` parameter is append to the url.

#### Cache Expiration
By default, only cache entries that are less than 1 hour old are returned. To extend this duration, add the cacheExpiration parameter to the URL. For instance, use `https://bca-url-proxy.azurewebsites.net/bca-url/sandbox/de?cacheExpiration=86400` to retrieve cache entries up to 24 hours old. The minimum value allowed is 900, which corresponds to 15 minutes.