using System;
using System.Diagnostics;
using System.Reflection;
using System.Collections;

using internal Pile;

namespace Pile
{
#if DEBUG
	[AlwaysInclude(IncludeAllMethods=true),Reflect(.StaticMethods)]
#endif
	static class Commands
	{
		[AttributeUsage(.Method, .ReflectAttribute|.DisallowAllowMultiple)]
		public struct DescriptionAttribute : Attribute
		{
			public String description;

			public this(String desc)
			{
				description = desc;
			}
		}

		// Extend this class with your own commands!
		// Non-Public methods will not be callable.

		public static void Help()
		{
			// Just a list of all methods
		}

		public static void Help(String command)
		{
			// Description and def of every method matching the string
		}

		public static void Clear()
		{
			// Clears the console
		}

		internal static class Interpreter
		{
			enum ParamsType
			{
				Invalid,

				String,
				SignedInt,
				UnsignedInt,
				Floating,
				Enum,

				Default
			}

			struct ParamsData
			{
				public StringView source;
				public ParamsType type;

				public StringView string;
				public int64 signedInt;
				public uint64 unsignedInt;
				public double floating;
			}

			static mixin PrintType(Type t)
			{
				let typeStr = t.ToString(.. scope:mixin .());
				var dot = typeStr.LastIndexOf('.');
				(dot == -1 ? typeStr : typeStr.Substring(dot + 1))
			}

			[DebugOnly]
			internal static void Interpret(StringView line, function void(Log.Types, StringView message) logOut, String diagnostic = null, String onAutoComplete = null)
			{
				// Syntax:
				// function call 'name params'
				// Strings: have to be quoted with "
				// SignedInt: decimal or hex notation (' ignored), no '.', has to fit integer size
				// UnsignedInt: same as SignedInt, but also no '-'
				// Floating: decimal notation, can contain or start with '.', 'f' or 'd' suffix is allowed but ignored
				// Enum: has to start with '.' and follow up with a valid entry. NEED TO HAVE [Reflect] (or forced reflection info) TO WORK

				var line;
				line.Trim();

				// Find function candidates
				var paramStart = line.IndexOf(' ');

				List<ParamsData> passedParams = scope .();
				if (paramStart > -1)
				{
					StringView paramLine = line.Substring(paramStart + 1, line.Length - (paramStart + 1));
					if (!ParseParams(paramLine..Trim(), passedParams))
					{
						String error = scope .("Invalid parameters:");
						var invCount = 0;
						for (let param in passedParams)
							if (param.type == .Invalid)
							{
								error.Append(scope $" ' {param.source} ',");
								invCount++;
							}

						if (error.EndsWith(','))
							error.RemoveFromEnd(1);

						if (diagnostic != null)
						{
							diagnostic.Append(error);
							// This may be because we're still in the process of typing the last one, so still display matches
							if (invCount == 1 && passedParams[passedParams.Count - 1].type == .Invalid)
								passedParams.RemoveAt(passedParams.Count - 1);
							else return;
						}
						else
						{
							logOut(.Error, error);
							return;
						}
					}
				}

				MethodInfo? bestMatch = null;
				int matchCount = 0;
				{
					// Get all qualifying methods
					let name = paramStart == -1 ? line : line.Substring(0, paramStart)..TrimEnd();
					int bestMatchedParams = 0;
					int bestMatchParamCount = int.MaxValue;
					bool bestIsParamCountMatch = false;
					int suggestedParamCount = int.MaxValue;
					for (let m in typeof(Commands).GetMethods(.Public|.Static))
					{
						if (name.Equals(m.Name, true))
						{
							if (m.ParamCount < passedParams.Count)
								continue;

							bool isParamCountMatch = m.ParamCount == passedParams.Count;
							int matchedParams = 0;
							for (var i < passedParams.Count)
							{
								let pType = m.GetParamType(i);
								if (!ParamsCompatible(pType, passedParams[i]))
									break;

								matchedParams++;
							}

							// An attempt to sort overloading and ignore-case overlaps somewhat intelligently
							// A method that the passed params are sufficient for is preferred
							// If that was not found (yet), a method that has more matches than the last with the least parameter count will be chosen
							if (matchedParams >= bestMatchedParams && (isParamCountMatch || (!bestIsParamCountMatch && m.ParamCount <= bestMatchParamCount)))
							{
								bestMatchParamCount = m.ParamCount;
								bestIsParamCountMatch = isParamCountMatch;
								bestMatchedParams = matchedParams;
								bestMatch = m;
							}
						}
						else
						{
							// If we just started typing and nothing matches so far, suggest something
							// that matches what we have so far and has few args
							if (passedParams.Count == 0 && bestMatchParamCount == int.MaxValue && m.ParamCount < suggestedParamCount)
							{
								let fn = m.Name;
								NAMECHECK:do
								{
									for (let n < name.Length)
										if (fn[n].ToLower != name[n].ToLower)
											break NAMECHECK;

									bestMatch = m;
									suggestedParamCount = m.ParamCount;
								}

							}

							continue;
						}

						matchCount++;
					}
					
					bool suggestionMatched = false;
					if (diagnostic != null) // Work with best guess for better info
					{
						// Best match is the closest we have and did not
						// necessarily qualify to count towards actual matches before
						if (matchCount == 0 && bestMatch != null)
						{
							matchCount++;
							suggestionMatched = true;
						}
					}

					if (matchCount == 0)
					{
						if (diagnostic != null)
						{
							if (diagnostic.Length > 0)
								diagnostic.Append('\n');
							diagnostic.Append("No command matches");
						}
						else
							logOut(.Error, "No command matches");

						return;
					}
					else if (suggestionMatched && onAutoComplete != null)
					{
						onAutoComplete.Append(bestMatch.Value.Name);
					}
				}

				let m = bestMatch.Value;

				// Print selected method
				if (diagnostic != null)
				{
					if (diagnostic.Length > 0)
						diagnostic.Append('\n');

					// Indicate there are multiple
					if (matchCount > 1)
						diagnostic.Append(scope $"({matchCount}) ");

					diagnostic.Append(m.Name);
					diagnostic.Append('(');
					for (let i < m.ParamCount)
					{
						diagnostic.Append(PrintType!(m.GetParamType(i)));
						diagnostic.Append(' ');
						diagnostic.Append(m.GetParamName(i));

						if (i < m.ParamCount - 1)
							diagnostic.Append(", ");
					}
					diagnostic.Append(')');
				}

				// Check and handle param compatibility issues
				{
					String error = scope .("Parameters don't match:");
					bool errsFound = false;
					for (let i < passedParams.Count) // We know that these are equal or less in count to the selectedMethods params
					{
						let pType = m.GetParamType(i);
						if (!ParamsCompatible(pType, passedParams[i], i == passedParams.Count - 1 ? diagnostic : null, i == passedParams.Count - 1 ? onAutoComplete : null))
						{
							let param = passedParams[i];
							error.Append(scope $" {param.type} '{(param.type == .String ? param.string : param.source)}' doesn't fit {PrintType!(pType)},");
							errsFound = true;
						}
					}

					if (errsFound)
					{
						if (error.EndsWith(','))
							error.RemoveFromEnd(1);

						if (diagnostic != null)
						{
							if (diagnostic.Length > 0)
								diagnostic.Append('\n');
							diagnostic.Append(error);
						}
						else
						{
							logOut(.Error, error);
							return;
						}
					}
					else if (passedParams.Count != m.ParamCount)
					{
						if (diagnostic != null)
						{
							if (diagnostic.Length > 0)
								diagnostic.Append('\n');
							diagnostic.Append("Not enough parameters provided");
						}
						else logOut(.Error, "Not enough parameters provided");
						return;
					}
				}

				// Actual call, only if this is not a diagnostic call
				CALL:if (diagnostic == null)
				{
					Debug.Assert(m.IsInitialized);
					Debug.Assert(m.ParamCount == passedParams.Count);

					Variant[] args = scope .[m.ParamCount];
					defer
					{
						for (var variant in args)
							variant.Dispose();
					}

					ARGMAKE:for (let i < m.ParamCount)
					{
						var argSlot = ref args[i];
						let passedParam = ref passedParams[i];
						let inType = m.GetParamType(i);

						// We have already checked that everything converts fine at this point

						mixin HandleInt<T>() where T : var, struct
						{
							T val = default;
							if (passedParam.type == .UnsignedInt)
								val = (T)passedParam.unsignedInt;
							else if (passedParam.type == .SignedInt)
								val = (T)passedParam.signedInt;
							else if (passedParam.type == .Default)
								val = default;
							else Debug.FatalError();
							Variant.Create(val)
						}

						mixin HandleFloat<T>() where T : var, struct
						{
							T val = default;
							if (passedParam.type == .Floating)
								val = (T)passedParam.floating;
							else if (passedParam.type == .UnsignedInt)
								val = (T)passedParam.unsignedInt;
							else if (passedParam.type == .SignedInt)
								val = (T)passedParam.signedInt;
							else if (passedParam.type == .Default)
								val = default;
							else Debug.FatalError();
							Variant.Create(val)
						}

						mixin HandleString()
						{
							String val = null;
							if (passedParam.type == .String)
								val = scope:CALL String(passedParam.string);
							else if (passedParam.type == .Default)
								val = scope:CALL String(String.Empty);
							else Debug.FatalError();
							val
						}

						switch (inType)
						{
						case typeof(uint8): argSlot = HandleInt!<uint8>();
						case typeof(uint16): argSlot = HandleInt!<uint16>();
						case typeof(uint32): argSlot = HandleInt!<uint32>();
						case typeof(uint64): argSlot = HandleInt!<uint64>();
						case typeof(uint): argSlot = HandleInt!<uint>();
						case typeof(int8): argSlot = HandleInt!<int8>();
						case typeof(int16): argSlot = HandleInt!<int16>();
						case typeof(int32): argSlot = HandleInt!<int32>();
						case typeof(int64): argSlot = HandleInt!<int64>();
						case typeof(int): argSlot = HandleInt!<int>();

						case typeof(double): argSlot = HandleFloat!<double>();
						case typeof(float): argSlot = HandleFloat!<float>();

						case typeof(String): argSlot = Variant.Create(HandleString!());
						case typeof(StringView): argSlot = Variant.Create(StringView(HandleString!()));

						default:
							bool pickDefault = passedParam.type == .Default;
							if (inType.IsEnum && (passedParam.type == .Enum || pickDefault))
							{
								for (let f in ((TypeInstance)inType).GetFields())
								{
									// Please note: this is highly illegal
									// From Variant.Create where T : struct
									if (passedParam.string.Equals(f.Name, true) || pickDefault)
									{
										Variant variant;
										variant.[Friend]mStructType = (int)Internal.UnsafeCastToPtr(inType);
										variant.[Friend]mData = 0;

										// Normally we'd check to see if inType.Size <= sizeof(int), but the reflect info
										// only stores an int right now, so i guess 64-bit enums are just screwed on 32 bit...
										// At least it seems like mData is not a disguised pointer the way it is used in Enum
										variant.[Friend]mData = f.[Friend]mFieldData.mData;

										argSlot = variant;
										continue ARGMAKE;
									}
								}
							}

							Debug.FatalError(); // This should never happen
							return;
						}
					}

					switch (m.Invoke(.(), params args))
					{
					case .Err(let err):
						logOut(.Error, scope $"Couldn't invoke command: {err}");
					case .Ok(var val):
						val.Dispose(); // Output will mostly happen through Log calls, so ignore this for now
					}
				}
			}

			static bool ParamsCompatible(Type paramType, ParamsData passedParam, String diagnostic = null, String autoComplete = null)
			{
				bool CheckSignedInts(int64 val)
				{
#unwarn
					return paramType == typeof(int8) && val <= int8.MaxValue && val >= int8.MinValue
						|| paramType == typeof(int16) && val <= int16.MaxValue && val >= int16.MinValue
						|| paramType == typeof(int32) && val <= int32.MaxValue && val >= int32.MinValue
						|| paramType == typeof(int) && val <= int.MaxValue && val >= int.MinValue
						|| paramType == typeof(int64);
				}

				bool CheckUnsignedInts(uint64 val)
				{
					return paramType == typeof(uint8) && val <= uint8.MaxValue && val >= uint8.MinValue
						|| paramType == typeof(uint16) && val <= uint16.MaxValue && val >= uint16.MinValue
						|| paramType == typeof(uint32) && val <= uint32.MaxValue && val >= uint32.MinValue
						|| paramType == typeof(uint) && val <= uint.MaxValue && val >= uint.MinValue
						|| paramType == typeof(uint64);
				}

				bool CheckFloats()
				{
					return paramType == typeof(float) || paramType == typeof(double);
				}

				switch (passedParam.type)
				{
				case .String:
					if (paramType == typeof(String) || paramType == typeof(Span<char8>) || paramType == typeof(StringView))
						return true;
				case .SignedInt:
					let val = passedParam.signedInt;
					if (CheckSignedInts(val) || val >= uint64.MinValue && CheckUnsignedInts((.)val)
						|| CheckFloats())
						return true;
				case .UnsignedInt:
					let val = passedParam.unsignedInt;
					if (val <= int64.MaxValue && CheckSignedInts((.)val) || CheckUnsignedInts(val)
						|| CheckFloats())
						return true;
				case .Floating:
					if (CheckFloats())
						return true;
				case .Enum:
					FieldInfo? bestMatch = null;
					int bestMatchedChars = 0;
					bool bestIsFullMatch = false;

					if (paramType.FieldCount == 0)
					{
						if (diagnostic != null)
						{
							if (diagnostic.Length > 0)
								diagnostic.Append('\n');
							diagnostic.Append(scope $"Enum {PrintType!(paramType)} has no values or is not marked with [Reflect]");
						}

						return false;
					}

					for (let f in ((TypeInstance)paramType).GetFields())
					{
						let str = f.[Friend]mFieldData.mName;

						if (passedParam.string.Length > str.Length)
							continue;

						var matchedChars = 0;
						for (; matchedChars < passedParam.string.Length; matchedChars++)
							if (str[matchedChars].ToLower != passedParam.string[matchedChars].ToLower)
								break;

						let isFullMatch = matchedChars == str.Length;
						if (matchedChars > bestMatchedChars && (!bestIsFullMatch || isFullMatch))
						{
							bestIsFullMatch = isFullMatch;
							bestMatchedChars = matchedChars;
							bestMatch = f;
						}
					}

					void NotFoundDiag()
					{
						if (diagnostic != null)
						{
							if (diagnostic.Length > 0)
								diagnostic.Append('\n');
							diagnostic.Append(scope $"\nEnum {PrintType!(paramType)} doesn't contain {passedParam.source}");
						}
					}

					if (bestMatch == null)
					{
						NotFoundDiag();
						return false;
					}

					if (!bestIsFullMatch)
					{
						NotFoundDiag();

						if (autoComplete != null)
							autoComplete.Append(bestMatch.Value.Name);

						return false;
					}
					else return true;
				case .Default:
					return true;
				default:
				}

				return false;
			}

			static bool ParseParams(StringView args, List<ParamsData> parseOut)
			{
				bool valid = true;
				bool isInString = false;
				int argStart = 0;
				char8 lastChar = '\0';

				void ProcessParam(StringView arg)
				{
					ParamsData data = .();
					ParseParam(arg, ref data);

					if (data.type == .Invalid)
						valid = false;

					parseOut.Add(data);
				}

				for (let i < args.Length)
				{
					let char = args[i];

					if (!isInString)
					{
						if (char == ' ')
						{
							if (i == argStart)
							{
								argStart++;
								continue;
							}
							else
							{
								let arg = args.Substring(argStart, i - argStart);
								argStart = i + 1;

								ProcessParam(arg); // Sets valid
							}
						}
						else if (i == argStart && char == '"')
							isInString = true;	
					}
					else if (char == '"' && lastChar != '\\')
						isInString = false;

					lastChar = char;
				}

				if (argStart < args.Length) // Process remaining
				{
					let arg = args.Substring(argStart, args.Length - argStart);
					argStart = args.Length + 1;

					ProcessParam(arg);
				}

				return valid;
			}

			static void ParseParam(StringView arg, ref ParamsData data)
			{
				data.source = arg;

				if (arg[0] == '"') // String
				{
					if (arg.Length > 1 && arg.EndsWith('"') && arg[arg.Length - 2] != '\\')
					{
						let string = arg.Substring(1, arg.Length - 2);

						char8 lastChar = '\0';
						bool stringValid = true;
						for (let char in string)
						{
							if (char == '"' && lastChar != '\\')
							{
								stringValid = false;
								break;
							}

							lastChar = char;
						}

						if (stringValid)
						{
							data.type = .String;
							data.string = string;
						}
					}
				}
				else if (arg[0] == 'd') // Default
				{
					if (arg == "default")
					{
						data.type = .Default;
					}
				}
				else if (arg[0] == '.' && arg.Length > 1 && !arg[1].IsNumber)
				{
					if (arg.Length > 1)
					{
						data.type = .Enum;
						data.string = arg.Substring(1);
					}
				}
				else // Some number
				{
					if (!arg.Contains('.')) // Integer
					{
						bool negative = arg[0] == '-';
						bool isHex = arg.Length > (negative ? 3 : 2) && arg[negative ? 1 : 0] == '0' && arg[negative ? 2 : 1].ToLower == 'x';
						bool unsigned = false;
						bool long = false;
						bool floating = false;
						var i = arg.Length - 1;
						for (; i >= 0; i--)
						{
							let nChar = arg[i].ToLower;
							if (nChar.IsNumber)
								break;

							if (!unsigned && !negative && nChar == 'u')
								unsigned = true;
							else if (!long && nChar == 'l')
								long = true;
							else if (!floating && !isHex && (nChar == 'f' || nChar == 'd'))
								floating = true;
							else break;
						}
						let numArg = arg.Substring(0, i + 1);

						if (numArg.Length > (negative ? 1 : 0))
						{
							bool success = false;
							int64 num = 0;
							uint64 uNum = 0;
							if (isHex) // Hex
							{
								if (unsigned) // Unsigned
								{
									if (uint64.Parse(numArg, .HexNumber) case .Ok(out uNum))
										success = true;
								}
								else if (int64.Parse(numArg, .HexNumber) case .Ok(out num)) // Signed
									success = true;
							}
							else // Decimal, hopefully
							{
								if (unsigned) // Unsigned
								{
									if (uint64.Parse(numArg, .Integer) case .Ok(out uNum))
										success = true;
								}
								else if (int64.Parse(numArg, .Integer) case .Ok(out num)) // Signed
									success = true;
							}

							if (success)
							{
								if (unsigned)
								{
									data.type = .UnsignedInt;
									data.unsignedInt = uNum;
								}
								else
								{
									data.type = .SignedInt;
									data.signedInt = num;
								}
								
							}
						}
					}
					else // Floating
					{
						var floating = arg;
						if (floating.EndsWith('d') || floating.EndsWith('f'))
							floating.RemoveFromEnd(1);

						var dot = 0;
						for (let c in arg)
							if (c == '.')
								dot++;

						if (floating.Length > 0 && !floating.EndsWith('.') && dot < 2 && double.Parse(floating) case .Ok(let val))
						{
							data.type = .Floating;
							data.floating = val;
						}
					}
				}
			}
		}
	}
}