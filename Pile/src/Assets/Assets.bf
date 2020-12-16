using System;
using System.IO;
using System.Collections;
using System.Diagnostics;
using JSON_Beef.Serialization;
using JSON_Beef.Types;

using internal Pile;

namespace Pile
{
	[Optimize]
	public class Assets
	{
		// Importers
		internal static Dictionary<String, Importer> Importers = new Dictionary<String, Importer>() ~ DeleteDictionaryAndKeysAndItems!(_);

		public static void RegisterImporter(StringView name, Importer importer)
		{
			for (let s in Importers.Keys)
				if (s == name)
				{
					Log.Error(scope $"Couldn't register importer as {name}, because another importer was already registered for under that name");
					return;
				}

			Importers.Add(new String(name), importer);
		}

		public static void UnregisterImporter(StringView name)
		{
			let res = Importers.GetAndRemove(scope String(name));

			// Delete
			if (res != .Err)
			{
				let val = res.Get();

				delete val.key;
				delete val.value;
			}
		}

		Packer packer = new Packer() { combineDuplicates = true } ~ delete _;
		List<Texture> atlas = new List<Texture>() ~ DeleteContainerAndItems!(_);

		Dictionary<Type, Dictionary<String, Object>> assets = new Dictionary<Type, Dictionary<String, Object>>() ~
			{
				for (let dic in _.Values)
					DeleteDictionaryAndKeysAndItems!(dic);

				delete _;
			};

		Dictionary<Type, List<StringView>> dynamicAssets = new Dictionary<Type, List<StringView>>() ~  DeleteDictionaryAndItems!(_);
		List<Package> loadedPackages = new List<Package>() ~ DeleteContainerAndItems!(_);
		String packagesPath = new String() ~ delete _;

		public int TextureCount => packer.SourceImageCount; // Not the same as TextureAssetCount
		public int AssetCount
		{
			get
			{
				int c = 0;
				for (let typeDict in assets.Values)
					c += typeDict.Count;

				return c;
			}
		}
		public int DynamicAssetCount
		{
			get
			{
				int c = 0;
				for (let nameList in dynamicAssets.Values)
					c += nameList.Count;

				return c;
			}
		}

		public delegate void PackageEvent(Package package);
		public Event<PackageEvent> OnLoadPackage ~ _.Dispose(); // Called after a package was loaded
		public Event<PackageEvent> OnUnloadPackage ~ _.Dispose(); // Called before a package was unloaded (assets not yet deleted)

		internal this()
		{
			// Get packages path
			Path.InternalCombine(packagesPath, Core.System.DataPath, "Packages");

			/*if (!Directory.Exists(packagesPath))
				Directory.CreateDirectory(packagesPath);*/
		}
		internal ~this() {}

		public bool Has<T>(String name) where T : class
		{
			let type = typeof(T);

			if (!assets.ContainsKey(type))
				return false;

			if (!assets.GetValue(type).Get().ContainsKey(name))
				return false;

			return true;
		}

		public bool Has<T>() where T : class
		{
			let type = typeof(T);

			if (!assets.ContainsKey(type))
				return false;

			return true;
		}

		public bool Has(Type type, String name)
		{
			if (!type.IsObject || !type.HasDestructor)
				return false;

			if (!assets.ContainsKey(type))
				return false;

			if (!assets.GetValue(type).Get().ContainsKey(name))
				return false;

			return true;
		}

		public bool Has(Type type)
		{
			if (!type.IsObject || !type.HasDestructor)
				return false;

			if (!assets.ContainsKey(type))
				return false;

			return true;
		}

		public T Get<T>(String name) where T : class
 		{
			 if (!Has<T>(name))
				 return null;

			 return (T)assets.GetValue(typeof(T)).Get().GetValue(name).Get();
		}

		public Object Get(Type type, String name)
		{
			if (!Has(type, name))
				return false;

			return assets.GetValue(type).Get().GetValue(name).Get();
		}

		public AssetEnumerator<T> Get<T>() where T : class
		{
			if (!Has<T>())
				return AssetEnumerator<T>(null);

			return AssetEnumerator<T>(assets.GetValue(typeof(T)).Get());
		}

		public Result<Dictionary<String, Object>.ValueEnumerator> Get(Type type)
		{
			if (!Has(type))
				return .Err;

			return assets.GetValue(type).Get().Values;
		}
		
		public Result<Package> LoadPackage(StringView packageName, bool packAndUpdateTextures = true)
		{
			Debug.Assert(packagesPath != null, "Initialize Core first!");

			for (int i = 0; i < loadedPackages.Count; i++)
				if (loadedPackages[i].Name == packageName)
					LogErrorReturn!(scope $"Package {packageName} is already loaded");

			List<Packages.Node> nodes = new List<Packages.Node>();
			List<String> importerNames = new List<String>();
			defer
			{
				DeleteContainerAndItems!(nodes);
				DeleteContainerAndItems!(importerNames);
			}

			// Read file
			{
				// Normalize path
				let packagePath = scope String();
				Path.InternalCombineViews(packagePath, packagesPath, packageName);

				if (Packages.ReadPackage(packagePath, nodes, importerNames) case .Err)
					return .Err;
			}

			let package = new Package();
			if (packageName.EndsWith(".bin")) Path.ChangeExtension(packageName, String.Empty, package.name);
			else package.name.Set(packageName);

			loadedPackages.Add(package);

			bool success = false;

			// If the following loop errors, clean up
			defer
			{
				if (!success)
					this.UnloadPackage(package.name, false).IgnoreError();
			}

			// Import each package node
			Importer importer;
			for (let node in nodes)
			{
				// Find importer
				if (node.Importer < (uint32)Importers.Count && Importers.ContainsKey(importerNames[(int)node.Importer]))
					importer = Importers.GetValue(importerNames[(int)node.Importer]);
				else if (node.Importer < (uint32)Importers.Count)
					LogErrorReturn!(scope $"Couldn't loat package {packageName}. Couldn't find importer {importerNames[(int)node.Importer]}");
				else
					LogErrorReturn!(scope $"Couldn't loat package {packageName}. Couldn't find importer name at index {node.Importer} of file's importer name array; index out of range");

				// Prepare data
				let name = StringView((char8*)node.Name.CArray(), node.Name.Count);

				let json = scope String((char8*)node.DataNode.CArray(), node.DataNode.Count);
				let res = JSONParser.ParseObject(json);
				if (res case .Err(let err))
					LogErrorReturn!(scope $"Couldn't loat package {packageName}. Error parsing json data for asset {name}: {err} ({json})");

				let dataNode = res.Get();
				defer delete dataNode;

				// Import node data
				importer.package = package;
				if (importer.Load(name, node.Data, dataNode) case .Err(let err))
					LogErrorReturn!(scope $"Couldn't loat package {packageName}. Error importing asset {name} with {importerNames[(int)node.Importer]}: {err}");
				importer.package = null;
			}

			success = true;

			// Finish
			if (packAndUpdateTextures)
				PackAndUpdateTextures();

			OnLoadPackage(package);
			return .Ok(package);
		}

		/// PackAndUpdate needs to be true for the texture atlas to be updated, but has some performance hit. Could be disabled on the first of two consecutive LoadPackage() calls.
		public Result<void> UnloadPackage(StringView packageName, bool packAndUpdateTextures = true)
		{
			Package package = null;
			for (int i = 0; i < loadedPackages.Count; i++)
				if (loadedPackages[i].Name == packageName)
				{
					package = loadedPackages[i];
					loadedPackages.RemoveAtFast(i);
				}

			if (package == null)
				LogErrorReturn!(scope $"Couldn't unload package {packageName}: No package with that name exists");

			OnUnloadPackage(package);

			for (let assetType in package.ownedAssets.Keys)
				for (let assetName in package.ownedAssets.GetValue(assetType).Get())
					RemoveAsset(assetType, assetName);

			for (let textureName in package.ownedTextureAssets)
				RemoveTextureAsset(textureName);

			if (packAndUpdateTextures)
				PackAndUpdateTextures();

			delete package;
			return .Ok;
		}

		public bool PackageLoaded(StringView packageName, out Package package)
		{
			for (let p in loadedPackages)
				if (p.Name == packageName)
				{
					package = p;
					return true;
				}

			package = null;
			return false;
		}

		/// Use Packages for static assets, use this for ones you don't know at compile time.
		public Result<void> AddDynamicAsset(StringView name, Object asset)
		{
			let type = asset.GetType();

			// Add object in assets
			let nameView = Try!(AddAsset(type, name, asset));

			// Add object location in dynamic lookup
			if (!dynamicAssets.ContainsKey(type))
				dynamicAssets.Add(type, new List<StringView>());

			dynamicAssets.GetValue(type).Get().Add(nameView);

			return .Ok;
		}

		/// Use Packages for static assets, use this for ones you don't know at compile time.
		/// PackAndUpdate needs to be true for the texture atlas to be updated, but has some performance hit. Could be disabled on the first of two consecutive calls.
		public Result<void> AddDynamicTextureAsset(StringView name, Bitmap bitmap, bool packAndUpdateTextures = true)
		{
			// Add object in assets
			let nameView = Try!(AddTextureAsset(name, bitmap));

			// Add object location in dynamic lookup
			if (!dynamicAssets.ContainsKey(typeof(Subtexture)))
				dynamicAssets.Add(typeof(Subtexture), new List<StringView>());

			dynamicAssets.GetValue(typeof(Subtexture)).Get().Add(nameView);

			if (packAndUpdateTextures)
				PackAndUpdateTextures();

			return .Ok;
		}

		public void RemoveDynamicAsset(Type type, StringView name)
		{
			if (!dynamicAssets.ContainsKey(type))
				return;

			// Remove asset if dynamics assets contained one with the name
			if (dynamicAssets.GetValue(type).Get().Remove(name))
				RemoveAsset(type, name);
		}

		/// PackAndUpdate needs to be true for the texture atlas to be updated, but has some performance hit. Could be disabled on the first of two consecutive calls.
		public void RemoveDynamicTextureAsset(StringView name, bool packAndUpdateTextures = true)
		{
			if (!dynamicAssets.ContainsKey(typeof(Subtexture)))
				return;

			// Remove asset if dynamics assets contained one with the name
			if (dynamicAssets.GetValue(typeof(Subtexture)).Get().Remove(name))
				RemoveTextureAsset(name);

			if (packAndUpdateTextures)
				PackAndUpdateTextures();
		}

		internal Result<StringView> AddAsset(Type type, StringView name, Object object)
		{
			Debug.Assert(Core.run);

			let nameString = new String(name);

			// Check if assets contains this name already
			if (Has(type, nameString))
			{
				delete nameString;

				LogErrorReturn!(scope $"Couldn't submit asset {name}: An object of this type ({type}) is already registered under this name");
			}

			if (!type.HasDestructor)
				LogErrorReturn!(scope $"Couldn't add asset {nameString} of type {object.GetType()}, because only classes can be treated as assets");

			if (!object.GetType().IsSubtypeOf(type))
				LogErrorReturn!(scope $"Couldn't add asset {nameString} of type {object.GetType()}, because it is not assignable to given type {type}");

			if (!assets.ContainsKey(type))
				assets.Add(type, new Dictionary<String, Object>());
			else if (assets.GetValue(type).Get().ContainsKey(nameString))
				LogErrorReturn!(scope $"Couldn't add asset {nameString} to dictionary for type {type}, because the name is already taken for this type");

			assets.GetValue(type).Get().Add(nameString, object);

			return .Ok(nameString);
		}

		internal Result<StringView> AddTextureAsset(StringView name, Bitmap bitmap)
		{
			Debug.Assert(Core.run);

			let nameString = new String(name);

			// Check if assets contains this name already
			if (Has(typeof(Subtexture), nameString))
			{
				delete nameString;

				LogErrorReturn!(scope $"Couldn't submit texture {name}: A texture is already registered under this name");
			}

			// Add to packer
			packer.AddBitmap(nameString, bitmap);

			// Even if somebody decides to have their own asset type for subtextures like class Sprite { Subtexture subtex; }
			// It's still good to store them here, because they would need to be in some lookup for updating on packer pack anyways
			// If you want to get the subtexture (even inside the importer function), just do Assets.Get<Subtexture>(name); (this also makes it clear that you are not the one to delete it)

			// Add to assets
			let type = typeof(Subtexture);
			if (!assets.ContainsKey(type))
				assets.Add(type, new Dictionary<String, Object>());
			else if (assets.GetValue(type).Get().ContainsKey(nameString))
				LogErrorReturn!(scope $"Couldn't add asset {nameString} to dictionary for type {type}, because the name is already taken for this type");

			let tex = new Subtexture();
			assets.GetValue(type).Get().Add(nameString, tex); // Will be filled in on PackAndUpdate()

			return .Ok(nameString);
		}

		internal void RemoveAsset(Type type, StringView name)
		{
			let string = scope String(name);

			if (!assets.ContainsKey(type))
				return;

			let res = assets.GetValue(type).Get().GetAndRemove(string);
			if (res case .Err) return; // Asset doesnt exist

			let pair = res.Get();

			delete pair.key;
			delete pair.value;
			
			// Delete unused dicts
			if (assets.GetValue(type).Get().Count == 0)
			{
				let dict = assets.GetAndRemove(type).Get();
				delete dict.value;
			}
		}

		internal void RemoveTextureAsset(StringView name)
		{
			let string = scope String(name);

			// Remove from packer
			packer.RemoveSource(name);

			// Remove from assets
			let type = typeof(Subtexture);
			if (!assets.ContainsKey(type))
				return;

			let res = assets.GetValue(type).Get().GetAndRemove(string);
			if (res case .Err) return; // Asset doesnt exist

			let pair = res.Get();

			delete pair.key;
			delete pair.value;
			
			// Delete unused dicts
			if (assets.GetValue(type).Get().Count == 0)
			{
				let dict = assets.GetAndRemove(type).Get();
				delete dict.value;
			}
		}

		internal void PackAndUpdateTextures()
		{
			Debug.Assert(Core.run);

			// Pack sources
			let res = packer.Pack();

			if (res case .Err) return; // We can't or shouldn't pack now
			var output = res.Get();

			// Apply bitmaps to textures in atlas
			int i = 0;
			for (; i < output.Pages.Count; i++)
			{
				if (atlas.Count <= i)
					atlas.Add(new Texture(output.Pages[i]));
				else atlas[i].Set(output.Pages[i]);

				delete output.Pages[i];
			}

			// Delete unused textures from atlas
			while (i < atlas.Count)
				delete atlas.PopBack();

			// Update all Subtextures
			for (var entry in output.Entries)
			{
				// Find corresponding subtex
				let subtex = Get<Subtexture>(entry.key);

				subtex.Reset(atlas[entry.value.Page], entry.value.Source, entry.value.Frame);
				delete entry.value; // Will also delete the key, because that is the same string as the name property
			}

			output.Entries.Clear(); // We deleted these in our loops, no need to loop again
			output.Pages.Clear();

			// Get rid of output
			delete output;
		}

		// Basically copy-pasta from Dictionary.ValueEnumerator
		public struct AssetEnumerator<TAsset> : IEnumerator<TAsset>, IResettable
		{
			private Dictionary<String, Object> mDictionary;
			private int_cosize mIndex;
			private TAsset mCurrent;

			const int_cosize cDictEntry = 1;
			const int_cosize cKeyValuePair = 2;

			public this(Dictionary<String, Object> dictionary)
			{
				mDictionary = dictionary;
				mIndex = 0;
				mCurrent = default;
			}

			public bool MoveNext() mut
			{
		        // Use unsigned comparison since we set index to dictionary.count+1 when the enumeration ends.
		        // dictionary.count+1 could be negative if dictionary.count is Int32.MaxValue
				while ((uint)mIndex < (uint)mDictionary.[Friend]mCount)
				{
					if (mDictionary.[Friend]mEntries[mIndex].mHashCode >= 0)
					{
						mCurrent = (TAsset)mDictionary.[Friend]mEntries[mIndex].mValue;
						mIndex++;
						return true;
					}
					mIndex++;
				}

				mIndex = mDictionary.[Friend]mCount + 1;
				mCurrent = default;
				return false;
			}

			public TAsset Current
			{
				get { return mCurrent; }
			}

			public ref String Key
			{
				get
				{
					return ref mDictionary.[Friend]mEntries[mIndex].mKey;
				}
			}

			public void Dispose()
			{
			}

			public void Reset() mut
			{
				mIndex = 0;
				mCurrent = default;
			}

			public Result<TAsset> GetNext() mut
			{
				if (mDictionary == null || !MoveNext())
					return .Err;
				return Current;
			}
		}
	}
}
