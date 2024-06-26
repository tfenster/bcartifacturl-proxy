using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Linq;
using System.Management.Automation;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace bcaup
{
    public class GetUrl
    {
        private readonly ILogger _logger;
        private static ConcurrentDictionary<string, CacheEntry> URL_CACHE = new ConcurrentDictionary<string, CacheEntry>();
        private const string VERSION = "1.3.0";

        public GetUrl(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<GetUrl>();
        }

        [Function("bca-url")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "bca-url/{type?}/{country?}/{version?}")] HttpRequestData req,
            string type,
            string version,
            string country,
            string select,
            string after,
            string before,
            string storageAccount,
            string sasToken,
            string accept_insiderEula,
            string doNotCheckPlatform,
            string doNotRedirect,
            string cacheExpiration)
        {
            _logger.LogInformation("C# HTTP trigger function processed a request.");

            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "text/plain; charset=utf-8");
            response.Headers.Add("X-bccontainerhelper-version", Environment.GetEnvironmentVariable("BCCH_VERSION"));
            response.Headers.Add("X-bcaup-version", VERSION);
            var bcchCommand = "";

            try
            {
                if (string.IsNullOrEmpty(type))
                    type = "Sandbox";
                var typeParam = validateTextParam("type", type);
                var countryParam = validateTextParam("country", country);
                var versionParam = validateTextParam("version", version);
                var selectParam = validateTextParam("select", select);
                var afterParam = validateTextParam("after", after);
                var beforeParam = validateTextParam("before", before);
                var storageAccountParam = validateTextParam("storageAccount", storageAccount);
                var sasTokenParam = validateTextParam("sasToken", sasToken);
                var accept_insiderEulaParam = GetAcceptInsiderEulaParam(accept_insiderEula, select, sasToken);

                var doNotCheckPlatformParam = string.Empty;
                if (IsValidParamSet(doNotCheckPlatform))
                    doNotCheckPlatformParam = " -doNotCheckPlatformParam";

                DateTimeOffset expiredAfter = GetExpiredAfter(cacheExpiration);

                bcchCommand = $"Get-BCArtifactUrl{typeParam}{countryParam}{versionParam}{selectParam}{afterParam}{beforeParam}{storageAccountParam}{sasTokenParam}{accept_insiderEulaParam}{doNotCheckPlatformParam}";
                response.Headers.Add("X-bccontainerhelper-command", bcchCommand);

                var url = "";

                if (URL_CACHE.TryGetValue(bcchCommand.ToLower(), out CacheEntry cachedUrl) && cachedUrl.createdOn > expiredAfter)
                {
                    response.Headers.Add("X-bcaup-from-cache", "true");
                    response.Headers.Add("X-bcaup-cache-timestamp", cachedUrl.createdOn.ToUnixTimeMilliseconds().ToString());
                    url = cachedUrl.url;
                }
                else
                {
                    response.Headers.Add("X-bcaup-from-cache", "false");
                    url = await GetUrlFromBackend(bcchCommand);
                    var ce = new CacheEntry
                    {
                        url = url,
                        createdOn = DateTime.Now
                    };
                    URL_CACHE.AddOrUpdate(bcchCommand.ToLower(), ce, (key, oldValue) => ce);
                }
                if (doNotRedirect == "true")
                    response.WriteString(url);
                else
                {
                    response.StatusCode = HttpStatusCode.Redirect;
                    response.Headers.Add("Location", url);
                }
            }
            catch (Exception ex)
            {
                response.StatusCode = HttpStatusCode.BadRequest;
                response.WriteString(ex.Message);
                if (!string.IsNullOrEmpty(bcchCommand))
                    response.WriteString($"Command was {bcchCommand}");
            }

            return response;
        }

        private async Task<string> GetUrlFromBackend(string bcchCommand)
        {
            var psCommmand = $". ./HelperFunctions.ps1; . ./Get-BCArtifactUrl.ps1; {bcchCommand}";
            _logger.LogDebug(psCommmand);
            var psCommandBytes = System.Text.Encoding.Unicode.GetBytes(psCommmand);
            var psCommandBase64 = Convert.ToBase64String(psCommandBytes);

            var startInfo = new ProcessStartInfo()
            {
                FileName = "pwsh",
                Arguments = $"-NoProfile -ExecutionPolicy unrestricted -EncodedCommand {psCommandBase64}",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            var process = Process.Start(startInfo);

            await process.WaitForExitAsync();

            var err = await process.StandardError.ReadToEndAsync();
            if (!string.IsNullOrWhiteSpace(err))
            {
                if (err.StartsWith("#< CLIXML\n"))
                {
                    err = err.Replace("#< CLIXML\n", "");
                    var deserialized = PSSerializer.DeserializeAsList(err);
                    err = String.Join("", deserialized);
                    err = Regex.Replace(err, "\\u001b\\[[0-9]{1,3}m", "");
                    throw new Exception(err);
                }
            }
            return await process.StandardOutput.ReadToEndAsync();
        }

        private string validateTextParam(string paramName, string paramValue)
        {
            var validatedParam = "";
            if (!string.IsNullOrEmpty(paramValue))
                validatedParam = $" -{paramName} \"{paramValue}\"";
            return validatedParam;
        }

        private bool IsValidParamSet(string param)
        {
            // Accept parameter without setting explict to true and with format "parameter=true"
            return (param is not null && (param.All(char.IsWhiteSpace) || param.ToLower() == "true"));
        }

        private string GetAcceptInsiderEulaParam(string accept_insiderEula, string select, string sasToken)
        {
            var accept_insiderEulaParam = " -accept_insiderEula";

            if (IsValidParamSet(accept_insiderEula))
                return accept_insiderEulaParam;

            return string.Empty;
        }

        private DateTimeOffset GetExpiredAfter(string cacheExpiration)
        {
            if (string.IsNullOrEmpty(cacheExpiration))
                return DateTimeOffset.Now.AddHours(-1);

            if (!int.TryParse(cacheExpiration, out int parsedCacheExpiration))
                throw new Exception(string.Format("The provided cache expiration value {0} is not a valid integer.", cacheExpiration));

            if (parsedCacheExpiration < 900) // minimum allowed is 15 minutes
                throw new ArgumentOutOfRangeException(string.Format("The provided cache expiration value {0} is invalid. It must be 900 or higher.", cacheExpiration));

            return DateTimeOffset.Now.AddSeconds(-parsedCacheExpiration);
        }

        private struct CacheEntry
        {
            public string url;
            public DateTimeOffset createdOn;
        }
    }
}
