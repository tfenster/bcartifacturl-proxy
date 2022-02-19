using System;
using System.Collections.Concurrent;
using System.Diagnostics;
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
        private const string VERSION = "1.0.1";

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
            string doNotCheckPlatform,
            string doNotRedirect)
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

                var doNotCheckPlatformParam = "";
                if (doNotCheckPlatform == "true")
                    doNotCheckPlatformParam = " -doNotCheckPlatformParam";

                bcchCommand = $"Get-BCArtifactUrl{typeParam}{countryParam}{versionParam}{selectParam}{afterParam}{beforeParam}{storageAccountParam}{sasTokenParam}{doNotCheckPlatformParam}";
                response.Headers.Add("X-bccontainerhelper-command", bcchCommand);

                if (URL_CACHE.TryGetValue(bcchCommand.ToLower(), out CacheEntry cachedUrl) && cachedUrl.expiration > DateTime.Now)
                {
                    response.Headers.Add("X-bcaup-from-cache", "true");
                    response.WriteString(cachedUrl.url);
                }
                else
                {
                    response.Headers.Add("X-bcaup-from-cache", "false");
                    var url = await GetUrlFromBackend(bcchCommand);
                    var ce = new CacheEntry
                    {
                        url = url,
                        expiration = type.ToLower() == "onprem" ? DateTime.Now.AddHours(24) : DateTime.Now.AddHours(1)
                    };
                    URL_CACHE.AddOrUpdate(bcchCommand.ToLower(), ce, (key, oldValue) => ce);
                    if (doNotRedirect == "true")
                        response.WriteString(url);
                    else
                    {
                        response.StatusCode = HttpStatusCode.Redirect;
                        response.Headers.Add("Location", url);
                    }

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

        private struct CacheEntry
        {
            public string url;
            public DateTime expiration;
        }
    }
}
