using System.Collections;
using System;

using internal Pile;

namespace Pile
{
	public struct InputState
	{
		public Keyboard keyboard;
		public Mouse mouse;
		internal readonly Controller[] controllers;
		public ref Controller GetController(int index) => ref controllers[index];

		internal this(Input input, int maxControllers)
		{
			controllers = new Controller[maxControllers];
			for (int i = 0; i < controllers.Count; i++)
				controllers[i] = Controller(input);

			keyboard = Keyboard(input);
			mouse = Mouse();
		}

		internal void Dispose()
		{
			keyboard.Dispose();
			mouse.Dispose();

			for	(int i = 0; i < controllers.Count; i++)
				controllers[i].Dispose();
			delete controllers;
		}

		internal void Step() mut
		{
			for	(int i = 0; i < controllers.Count; i++)
			{
				if (controllers[i].Connected)
					controllers[i].Step();
			}

			keyboard.Step();
			mouse.Step();
		}

		internal void Copy(InputState from) mut
		{
			for	(int i = 0; i < controllers.Count; i++)
			{
				if (from.controllers[i].Connected || controllers[i].Connected != from.controllers[i].Connected)
					controllers[i].Copy(from.controllers[i]);
			}

			keyboard.Copy(from.keyboard);
			mouse.Copy(from.mouse);
		}
	}
}
