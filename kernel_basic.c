/*  [1]: http://williamstallings.com/OS/
[2]: http://blog.rlove.org/2010/07/li...
[3]: http://lwn.net/Kernel/LDD3/
[4]: http://elinuxdd.com/
[5]: https://github.com/martinezjavie...
[6]: http://lwn.net/Articles/416690/
https://github.com/martinezjavier/ldd3
 *  kernel_basic.c - Demonstrating the module_init() and module_exit() macros.
 *  This is preferred over using init_module() and cleanup_module().
 */
#include <linux/module.h>	/* Needed by all modules */
#include <linux/kernel.h>	/* Needed for KERN_INFO */
#include <linux/init.h>		/* Needed for the macros */

static int __init kernel_hello_init(void)
{
	printk(KERN_INFO "Hello, kernel \n");
	return 0;
}

static void __exit kernel_hello_exit(void)
{
	printk(KERN_INFO "Goodbye, kernel\n");
	printk(KERN_INFO "Goodbye, kernel conflicts \n");
	
}

module_init(kernel_hello_init);
module_exit(kernel_hello_exit);
