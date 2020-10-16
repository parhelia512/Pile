using System;
using System.IO;
using System.Collections;
using System.Diagnostics;
using JSON_Beef.Serialization;
using JSON_Beef.Types;

namespace Pile
{
	public static class Assets
	{
		static RuntimePacker packer = new RuntimePacker(false) ~ delete _; // Subtextures are managed like all assets
		static Dictionary<Type, Dictionary<String, Object>> assets = new Dictionary<Type, Dictionary<String, Object>>();

		static ~this()
		{
			for (let dic in assets.Values)
				DeleteDictionaryAndKeysAndItems!(dic);

			delete assets;
		}

		public static bool Has<T>(String name) where T : Object
		{
			let type = typeof(T);

			if (!assets.ContainsKey(type))
				return false;

			if (!assets.GetValue(type).Get().ContainsKey(name))
				return false;

			return true;
		}

		public static bool Has(Type type, String name)
		{
			if (!type.IsObject)
				return false;

			if (!assets.ContainsKey(type))
				return false;

			if (!assets.GetValue(type).Get().ContainsKey(name))
				return false;

			return true;
		}

		public static T Get<T>(String name) where T : Object
 		{
			 if (!Has<T>(name))
				 return null;

			 return (T)assets.GetValue(typeof(T)).Get().GetValue(name).Get();
		}

		public static Object Get(Type type, String name)
		{
			if (!Has(type, name))
				return false;

			return assets.GetValue(type).Get().GetValue(name).Get();
		}

		/** The name string passed here will be directly referenced in the dictionary, so take a fresh one, ideally the same that is also referenced in package owned assets.
		*/
		internal static Result<void> AddAsset(Type type, String name, Object object)
		{
			if (!object.GetType().IsSubtypeOf(type))
				LogErrorReturn!(scope String("Couldn't add asset {0} of type {1}, because it is not assignable to given type {2}")..Format(name, object.GetType(), type));

			if (!assets.ContainsKey(type))
				assets.Add(type, new Dictionary<String, Object>());

			else if (assets.GetValue(type).Get().ContainsKey(name))
				LogErrorReturn!(scope String("Couldn't add asset {0} to dictionary for type {1}, because the name is already taken for this type")..Format(name, type));

			assets.GetValue(type).Get().Add(name, object);

			return .Ok;
		}

		internal static void RemoveAsset(Type type, String name)
		{
			if (!assets.ContainsKey(type))
				return;
			else if (!assets.GetValue(type).Get().ContainsKey(name))
				return;

			let pair = assets.GetValue(type).Get().GetAndRemove(name).Get();

			// Delete unused
			delete pair.key;
			delete pair.value;
			
			if (assets.GetValue(type).Get().Count == 0)
			{
				let dict = assets.GetAndRemove(type).Get();
				delete dict.value;
			}
				
		}

		// BELOW NOT YET CALLLED
		internal static Result<void> AddPackerBitmap(String name, Bitmap bitmap)
		{
			let type = typeof(Subtexture);
			if (!assets.ContainsKey(type))
				assets.Add(type, new Dictionary<String, Object>());

			else if (assets.GetValue(type).Get().ContainsKey(name))
				LogErrorReturn!(scope String("Couldn't add asset {0} to dictionary for type {1}, because the name is already taken for this type")..Format(name, type));

			assets.GetValue(type).Get().Add(name, packer.AddToCurrentPack(name, bitmap));

			return .Ok;
		}
		
		internal static void CommitPackerBitmaps(String packName)
		{
			packer.CommitCurrentPack(packName);
		}

		internal static void RemovePackerBitmaps(String packName)
		{
			packer.RemovePack(packName);
		}
	}
}
