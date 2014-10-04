/*  
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
	printk(KERN_INFO "Sorry, kernel conflict\n");
}

module_init(kernel_hello_init);
module_exit(kernel_hello_exit);
