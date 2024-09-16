using System.Collections.Concurrent;
using System.Diagnostics;
using System.Management.Automation;
using System.Net;
using System.Text.RegularExpressions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace bcaup;
public partial class GetUrl(ILoggerFactory loggerFactory)
{
    private readonly ILogger _logger = loggerFactory.CreateLogger<GetUrl>();
    private static readonly ConcurrentDictionary<string, CacheEntry> URL_CACHE = new();
    private const string VERSION = "1.4.0";
    private static readonly string? BCCH_VERSION = Environment.GetEnvironmentVariable("BCCH_VERSION");

    [GeneratedRegex("\\u001b\\[[0-9]{1,3}m")]
    private static partial Regex FixedRegex();

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
        string accept_insiderEula,
        string doNotCheckPlatform,
        string doNotRedirect,
        string cacheExpiration)
    {
        _logger.LogInformation("C# HTTP trigger function processed a request.");

        var response = req.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "text/plain; charset=utf-8");
        response.Headers.Add("X-bccontainerhelper-version", BCCH_VERSION ?? "Unknown");
        response.Headers.Add("X-bcaup-version", VERSION);
        var bcchCommand = string.Empty;

        try
        {
            if (string.IsNullOrEmpty(type))
                type = "Sandbox";
            var typeParam = ValidateTextParam(nameof(type), type);
            var countryParam = ValidateTextParam(nameof(country), country);
            var versionParam = ValidateTextParam(nameof(version), version);
            var selectParam = ValidateTextParam(nameof(select), select);
            var afterParam = ValidateTextParam(nameof(after), after);
            var beforeParam = ValidateTextParam(nameof(before), before);
            var storageAccountParam = ValidateTextParam(nameof(storageAccount), storageAccount);
            var accept_insiderEulaParam = GetAcceptInsiderEulaParam(accept_insiderEula);

            var doNotCheckPlatformParam = string.Empty;
            if (IsValidParamSet(doNotCheckPlatform))
                doNotCheckPlatformParam = " -doNotCheckPlatform";

            DateTimeOffset expiredAfter = GetExpiredAfter(cacheExpiration);

            bcchCommand = $"Get-BCArtifactUrl{typeParam}{countryParam}{versionParam}{selectParam}{afterParam}{beforeParam}{storageAccountParam}{accept_insiderEulaParam}{doNotCheckPlatformParam}";
            response.Headers.Add("X-bccontainerhelper-command", bcchCommand);

            var url = string.Empty;

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
                await response.WriteStringAsync(url);
            else
            {
                response.StatusCode = HttpStatusCode.Redirect;
                response.Headers.Add("Location", url);
            }
        }
        catch (Exception ex)
        {
            response.StatusCode = HttpStatusCode.BadRequest;
            await response.WriteStringAsync(ex.Message);
            if (!string.IsNullOrEmpty(bcchCommand))
                await response.WriteStringAsync($"Command was {bcchCommand}");
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
        using var process = Process.Start(startInfo) ?? throw new Exception("Failed to start the pwsh process!");

        await process.WaitForExitAsync();

        var err = await process.StandardError.ReadToEndAsync();
        if (!string.IsNullOrWhiteSpace(err))
        {
            if (err.StartsWith("#< CLIXML\n"))
            {
                err = err.Replace("#< CLIXML\n", "");
                var deserialized = PSSerializer.DeserializeAsList(err);
                err = string.Join("", deserialized);
                err = FixedRegex().Replace(err, "");
                throw new Exception(err);
            }
        }
        return await process.StandardOutput.ReadToEndAsync();
    }

    private static string ValidateTextParam(string paramName, string paramValue)
    {
        return !string.IsNullOrEmpty(paramValue) ? $" -{paramName} \"{paramValue}\"" : string.Empty;
    }

    private static bool IsValidParamSet(string? param)
    {
        // Accept parameter without setting explict to true and with format "parameter=true"
        return !string.IsNullOrWhiteSpace(param) && param.Equals("true", StringComparison.CurrentCultureIgnoreCase);
    }

    private static string GetAcceptInsiderEulaParam(string accept_insiderEula)
    {
        var accept_insiderEulaParam = " -accept_insiderEula";

        if (IsValidParamSet(accept_insiderEula))
            return accept_insiderEulaParam;

        return string.Empty;
    }

    private static DateTimeOffset GetExpiredAfter(string cacheExpiration)
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
