# bcartifacturl-proxy

Proxy for artifact URLs read by bccontainerhelper. You can run this on your own environment with the docker image tobiasfenster/bcaup or you can use the publicly available Azure Function https://bca-url-proxy.azurewebsites.net/bca-url/ e.g. like this: https://bca-url-proxy.azurewebsites.net/bca-url/sandbox/de/19


### Examples

| Get-BCArtifactUrl | Url |
| :-- | :-- |
| ```Get-BCArtifactUrl -type Sandbox``` | `https://bca-url-proxy.azurewebsites.net/bca-url/sandbox` |
| ```Get-BCArtifactUrl -select NextMajor -accept_insiderEula``` | `https://bca-url-proxy.azurewebsites.net/bca-url?select=nextmajor?accept_insiderEula` |
