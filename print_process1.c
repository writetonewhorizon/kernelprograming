/*-------------------------------------------------------------------
 * print_process1.c -- 	print some fields of the task_structure
 *			for the running processes
 *
 * Notes:
 *  -- interesting functions
 *	find_task_by_pid_ns - find a task structure given its
 *      	              pid number and name space
 *	  from /opt/carme/kernel/linux-2.6.35.9-CARME/kernel/pid.c
 *        line: 383; however the symbol find_task_by_pid_ns is not
 *        is not exported.
 *        On the other hand, find_task_by_pid_ns is wrapper for
 *            pid_task(find_pid_ns(nr, ns), PIDTYPE_PID);
 *        where both symbols pid_task, and find_pid_ns are exported,
 *        and PIDTYPE_PID is defined in <linux/pid.h>.
 *        The arguments of pid_find() are:
 *           pid_t nr: numeric process ID
 *           struct pid_namespace *ns: pid name space pointer
 *           Currently, only init_pid_ns (defined in kernel/pid.c) is used.
 *        The return value of pid_find() is a pointer to struct pid.
 *
 *        The arguments of pid_task() are:
 *           struct pid *pid   : the result of functin find_pid_ns()
 *           enum pid_type type: pass PIDTYPE_PID
 *        The return value of pid_task() is a pointer to struct task_struct 
 *
 *  -- kernel 2.6.30.2:  uid/euid/gid/egid attached to the
 *                       task_struct in struct cred
 *
 * Compile the module using the make file (as you): Makefile 
 *
 *   $make
 * 
 * If you want to install the module into the extra branch
 * type (as root)
 *
 * # make modules_install 
 *
 * and perhaps: #depmod
 *
 * load the module
 *   #insmod ./print_process1.ko   or modprobe print_process1
 *
 * The module is actually not loaded, because its init() function returns
 * the error -ENOANO. It is OK if you see the error message
 *  modprobe: can't load module print_process1 (extra/print_process1.ko): No anode
 *
 * unload the module (perhaps not required)
 *   #rmmod print_process1         or modprobe -r print_process1
 *
 * module parameters
 *    -- user_id: print only processes with this user id
 *    -- cmd: print only processes that are executing this command 
 *
 * Do that in the console window (minicom) to see the output of the module 
 * immediately. Otherwise, display the log (in another window)
 *   # tail /var/log/messages
 *
 *-------------------------------------------------------------------------*/

#include <linux/module.h>   /* needed by modules, struct module */
#include <linux/init.h>     /* modules_init/_exit macros */
#include <linux/kernel.h>   /* KERN_ALERT list_head */
#include <linux/list.h>     /* list_head, list iterator*/
#include <linux/sched.h>
#include <linux/pid.h>	    /* structs pid, pid_link, iterator macros */


MODULE_LICENSE("Dual BSD/GPL");

#define DFT_USER_ID		(0)	/* print only processes of root*/
#define DFT_CMD			("") 	/* print ALL processes */
#define DFT_PID_MAX		(5000)	/* default maximum pid */
/* 
 * functions used in this file
 */
static void print_task(struct task_struct *);
static void print_children(struct task_struct *);
/*
 * module parameters
 */
static int user_id = DFT_USER_ID;	/* processes of this user */
module_param(user_id, int, S_IRUGO);
static char *cmd = DFT_CMD;		/* command to print */
module_param(cmd, charp, S_IRUGO);
static int pid_max = DFT_PID_MAX;	/* max pid */
module_param(pid_max, int, S_IRUGO);

static char *pid_type[] = { "PID", "PGID", "SID" };

/*
 * module initialization
 * Notes
 *  use the list iterator for_each_process as
 *  for_each_process(iterator pointer variable)
 *	iterator is pointer to task_structure
 */
static int __init print_process1_init(void)
{
	long li;
	struct task_struct     *pTask1 = NULL; /* init process*/
	struct task_struct     *pTask;  /* iterator variable through process chain */
	/*
	 * print kernel's task structure and his children
	 */	 
	printk(KERN_INFO "*** Print task structure (%d bytes) of the init process***\n",
               sizeof(struct task_struct));
//	pTask1 = pid_task(find_pid_ns(nr, ns), PIDTYPE_PID);
	pTask1 = pid_task(find_pid_ns(1, &init_pid_ns), PIDTYPE_PID);
	if (pTask1) {	
		print_task(pTask1);
		print_children(pTask1);
	} else {
		printk("task structure for init process not found\n");
		return -ENOANO;
	}
	printk(KERN_INFO "*** Iterate over task structures of other tasks ***\n");
	/*
	 * iterate over tasks
         *  -- display the credentials of the "objective context" specified by
	 *     real_cred. It is used when some other task is attempting to
	 *     to affect this task
         *  -- display the credentials of the "subjective context" specified by
	 *     cred. It is used when this task is acting on some other
	 *     objects like a file, a task, a key, etc.
 	 *  Often those credentials are the same.
	 */
	for_each_process(pTask) {
           if ((strlen(cmd) > 0) && (strcmp(pTask->comm,cmd)) != 0) continue;
	   printk("**** task: &:%p pid:%d tgid:%d comm:%s\n credentials",
		pTask, pTask->pid, pTask->tgid, pTask->comm);	
	   if (pTask->real_cred) {
		printk(" obj:[&:%p,uid:%d,euid:%d,gid:%d,egid;%d]",
		pTask->real_cred, pTask->real_cred->uid, pTask->real_cred->gid,
		pTask->real_cred->euid, pTask->real_cred->egid);
           }
	   if (pTask->cred) {
		printk(" subj:[&:%p,uid:%d,euid:%d,gid:%d,egid;%d]",
		pTask->cred, pTask->cred->uid, pTask->cred->gid, pTask->cred->euid, 
		pTask->cred->egid);
           }
	   printk("\n");
	   if (pTask->cred && (pTask->cred->euid == user_id) && 
              ((strlen(cmd) == 0) || (strcmp(pTask->comm,cmd)) == 0)) {
		print_task(pTask);
	 	print_children(pTask);
  	   }
	}
	/*
	 * iterate over PIDs
	 *   if a PID is valid then there is an instance of struct pid
	 *     use the kernel function find_vpid() from kernel/pid.c
	 *     find_vpid() hashes the PID and searches the PID in the
	 *     hash chain formed by struct pid elements, linked by
	 *     field pid_chain. It returns a ptr to struct pid or NULL.
	 *   the array tasks[] in struct pid give the tasks that use
	 *   this pid for all PIDTYPES
	 *     use the kernel function pid_task from kernel/pid.c
	 *     to find the associated task structure if it exists 
	 *     for that type
	 */
	printk(KERN_INFO "*** Iterate over PIDs ***\n");
	for (li = 0; li <  pid_max; li++) {
		int j;
		struct pid *pid = find_vpid(li);
		if (pid) {
			printk(KERN_INFO "PID:%ld", li);
			for (j = 0; j < PIDTYPE_MAX; j++) {
                        	printk("%5s:tasks[first:%p,&task:%p]",
                        	pid_type[j], pid->tasks[j].first, pid_task(pid,j));
			}
			printk("\n");
		}
	}
	return -ENOANO;
}
/* 
 * module exit
 */
static void __exit print_process1_exit(void)
{
	printk(KERN_INFO "Goodbye, print_process1\n");
}
/*
 * print some fields of a process descriptor
 *    -- iterate on a thread group if existing
 *    -- print the pid_link fields
 */
static void print_task(struct task_struct *pTask)
{
	int i,j;
	struct pid_link *pPidLink;
	struct task_struct *pTask1, *pTask2;

	printk(KERN_INFO " more on task_struct of cmd:%s\n"
                         " ts:&:%p pid:%d tgid:%d pgrp:%d sess-ldr:%d grp_ldr:%p\n"
                         " ts:tasks[&:%p p:%p,n:%p]\n",
       		pTask->comm, pTask, pTask->pid, pTask->tgid, 
 		task_pgrp_vnr(pTask), task_session_vnr(pTask),
        	pTask->group_leader, &pTask->tasks, pTask->tasks.prev, pTask->tasks.next);
	printk(KERN_INFO " ts:group_leader:%p,thread_grp[&:%p,p:%p,n:%p]\n",
	  	pTask->group_leader, &pTask->thread_group, 
		pTask->thread_group.prev, pTask->thread_group.next);
	/*
 	 * iterate on thread group if existing
	 */
        printk(KERN_INFO " iterate over thread group\n");
	
	list_for_each_entry_safe(pTask1, pTask2, &pTask->thread_group, thread_group) {
	    printk(KERN_INFO "    ts:addr:%p pid:%d tgid:%d pgrp:%d sess-ldr:%d grp_ldr:%p cmd:%s\n"
                             "    ts:tasks[&:%p p:%p,n:%p]\n",
          pTask1, pTask1->pid, pTask1->tgid, task_pgrp_vnr(pTask1), task_session_vnr(pTask1),
          pTask1->group_leader, pTask1->comm, &pTask1->tasks, pTask1->tasks.prev, pTask1->tasks.next);
        }
	/*
	 * print the pid_link pids[] fields
	 */
	printk(KERN_INFO " iterate over pids array\n");

        for (i = 0,pPidLink=pTask->pids; i < PIDTYPE_MAX; i++,pPidLink++) {
	    if (pPidLink == NULL) continue;
	    if (pPidLink->node.pprev)
                printk(KERN_INFO "%6s:pid_link:[hl_node[&:%p,n:%p,*p:%p],pid&:%p\n",
                    pid_type[i], &pPidLink->node, pPidLink->node.next, *pPidLink->node.pprev, pPidLink->pid);
	    if (pPidLink->pid && pPidLink->pid->numbers && 
                pPidLink->pid->numbers->pid_chain.pprev) {
		printk(KERN_INFO "    pid:[ct:%d,lv:%d,upid[nr:%d,ns:%p,pid_chain:[&:%p,n:%p,*p:%p]]]\n",
		atomic_read(&pPidLink->pid->count), pPidLink->pid->level, 
		pPidLink->pid->numbers->nr, pPidLink->pid->numbers->ns,
		&pPidLink->pid->numbers->pid_chain, pPidLink->pid->numbers->pid_chain.next,
		*pPidLink->pid->numbers->pid_chain.pprev);

                for (j = 0; j < PIDTYPE_MAX; j++) {
                        printk(KERN_INFO "    pid:%6s:tasks[first:%p]\n",
                        pid_type[j], pPidLink->pid->tasks[j].first);
                }
	    }
	}
}

/*
 * print children
 */
static void print_children(struct task_struct *thisTask)
{
	struct list_head   *pList;
	struct task_struct *pTask;
	int n_children = 0;

	printk(KERN_INFO " iterate over children\n");

	list_for_each(pList, &thisTask->children) {
		n_children++;
		pTask=list_entry(pList, struct task_struct, sibling);
		printk(KERN_INFO "    ch-ts:addr:%p pid:%d tgid:%d pgrp:%d sess-ldr:%d grp_ldr:%p cmd:%s\n"
                             "    ch-ts:tasks[&:%p p:%p,n:%p]\n",
          	pTask, pTask->pid, pTask->tgid, task_pgrp_vnr(pTask), task_session_vnr(pTask),
          	pTask->group_leader, pTask->comm, &pTask->tasks, pTask->tasks.prev, pTask->tasks.next);
	}
	if (n_children == 0)
		printk(KERN_INFO " *** no children\n");
}


module_init(print_process1_init);
module_exit(print_process1_exit);
