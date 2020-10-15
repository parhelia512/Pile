using SDL2;
using System;

using internal Pile.Implementations;

namespace Pile.Implementations
{
	public class SDL_Context : ISystemOpenGL.Context
	{
		SDL.SDL_GLContext context;
		SDL_Window window;

		internal this(SDL_Window window)
		{
			this.window = window;
			context = SDL.GL_CreateContext(window.window);
		}

		public override void Dispose()
		{
			SDL.GL_DeleteContext(context);
			disposed = true;
		}

		public override void MakeCurrent()
		{
			SDL.SDL_GL_MakeCurrent(window.window, context);
		}

		bool disposed;
		public override bool Disposed => disposed;
	}
}
