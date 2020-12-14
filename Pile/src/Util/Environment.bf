using System.Collections;

namespace System
{
	extension Environment
	{
		public static void GetEnvironmentVariable(String key, String outString)
		{
			let dict = new Dictionary<String, String>();
			Environment.GetEnvironmentVariables(dict);

			if (!dict.ContainsKey(key)) return;

			outString.Append(dict[key]);
			DeleteDictionaryAndKeysAndItems!(dict);
		}
	}
}