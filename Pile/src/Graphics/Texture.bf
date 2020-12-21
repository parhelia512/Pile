using System;
using System.Diagnostics;

using internal Pile;

namespace Pile
{
	public class Texture
	{
		public static TextureFilter DefaultTextureFilter = TextureFilter.Linear;

		public readonly TextureFormat format;

		public uint32 Width { get; private set; }
		public uint32 Height { get; private set; }

		public uint32 Size => Width * Height * format.Size();

		TextureFilter filter;
		public TextureFilter Filter
		{
			get => filter;
			set => SetFilter(filter = value);
		}

		TextureWrap wrapX;
		public TextureWrap WrapX
		{
			get => wrapX;
			set => SetWrap(wrapX = value, wrapY);
		}
		
		TextureWrap wrapY;
		public TextureWrap WrapY
		{
			get => wrapY;
			set => SetWrap(wrapX, wrapY = value);
		}

		public extern bool IsFrameBuffer { get; }

		public this(uint32 width, uint32 height, TextureFormat format = .Color, TextureFilter filter = DefaultTextureFilter)
		{
			Debug.Assert(Core.Graphics != null, "Core needs to be initialized before creating platform dependent objects");

			Debug.Assert(width > 0 || height > 0, "Texture size must be larger than 0");

			Width = width;
			Height = height;
			this.format = format;
			this.filter = filter;

			Initialize();
		}

		public this(Bitmap bitmap, TextureFilter filter = DefaultTextureFilter)
			: this(bitmap.Width, bitmap.Height, .Color, filter)
		{
			SetData(&bitmap.Pixels[0]);
		}

		public void CopyTo(Bitmap bitmap)
		{
			bitmap.ResizeAndClear(Width, Height);

			var span = Span<Color>(bitmap.Pixels);
			GetData(&span[0]);
		}

		public Result<void> Set(Bitmap bitmap)
		{
			if ((bitmap.Width != Width || bitmap.Height != Height) && (ResizeAndClear(bitmap.Width, bitmap.Height) case .Err)) return .Err; // Resize this if needed
			SetData(&bitmap.Pixels[0]);

			return .Ok;
		}

		public Result<void> ResizeAndClear(uint32 width, uint32 height)
		{
			if (width <= 0 || height <= 0)
				LogErrorReturn!("Texture size must be larger than 0");

			if (Width != width || Height != height)
			{
				Width = width;
				Height = height;

				ResizeAndClearInternal(width, height);
			}
			return .Ok;
		}

		public Result<void> SetColor(ref Span<Color> buffer) => SetData<Color>(ref buffer);
		public Result<void> SetData<T>(ref Span<T> buffer)
		{
			if (sizeof(T) * buffer.Length * sizeof(T) < (.)Size)
				LogErrorReturn!("Buffer is smaller than the Size of the Texture");

			SetData(&buffer[0]);
			return .Ok;
		}

		public Result<void> GetColor(ref Span<Color> buffer) => GetData<Color>(ref buffer);
		public Result<void> GetData<T>(ref Span<T> buffer)
		{
			if (sizeof(T) * buffer.Length * sizeof(T) < (.)Size)
				LogErrorReturn!("Buffer is smaller than the Size of the Texture");

			GetData(&buffer[0]);
			return .Ok;
		}

		protected internal extern void Initialize();
		protected internal extern void ResizeAndClearInternal(uint32 width, uint32 height);
		protected internal extern void SetFilter(TextureFilter filter);
		protected internal extern void SetWrap(TextureWrap x, TextureWrap y);
		protected internal extern void SetData(void* buffer);
		protected internal extern void GetData(void* buffer);
	}
}
