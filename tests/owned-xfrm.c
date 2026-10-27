#define OWNED_XFRM_TEST
#include "../tools/ikev2/owned-xfrm.c"
#include <assert.h>
#include <sys/wait.h>
static char packet[1024];
static struct nlmsghdr *policy(uint32_t reqid,uint32_t ifid,int mixed){
 memset(packet,0,sizeof(packet));struct nlmsghdr *h=(void *)packet;
 h->nlmsg_type=XFRM_MSG_NEWPOLICY;h->nlmsg_len=NLMSG_LENGTH(sizeof(struct xfrm_userpolicy_info));
 struct xfrm_userpolicy_info *p=NLMSG_DATA(h);p->index=123;p->dir=XFRM_POLICY_OUT;
 struct xfrm_user_tmpl templates[2]={{.reqid=reqid},{.reqid=reqid+1}};
 attr(h,XFRMA_TMPL,templates,mixed?sizeof(templates):sizeof(templates[0]));
 if(ifid)attr(h,XFRMA_IF_ID,&ifid,sizeof(ifid));
 return h;
}
static struct nlmsghdr *sa(uint32_t reqid,uint32_t ifid){
 memset(packet,0,sizeof(packet));struct nlmsghdr *h=(void *)packet;
 h->nlmsg_type=XFRM_MSG_NEWSA;h->nlmsg_len=NLMSG_LENGTH(sizeof(struct xfrm_usersa_info));
 struct xfrm_usersa_info *s=NLMSG_DATA(h);s->reqid=reqid;s->id.spi=0x1234;s->id.proto=50;s->family=AF_INET;
 if(ifid)attr(h,XFRMA_IF_ID,&ifid,sizeof(ifid));
 return h;
}
int main(void){
 struct item item;
 assert(parse(policy(OWN_ID,OWN_ID,0),&item));assert(item.policy && item.id.policy.index==123 && item.id.policy.dir==XFRM_POLICY_OUT);
 assert(!parse(policy(OWN_ID,99,0),&item));assert(!parse(policy(99,OWN_ID,0),&item));assert(!parse(policy(OWN_ID,0,0),&item));
 assert(!parse(policy(OWN_ID,OWN_ID,1),&item));
 struct nlmsghdr *h=policy(OWN_ID,OWN_ID,0);struct xfrm_mark mark={.v=7,.m=255};attr(h,XFRMA_MARK,&mark,sizeof(mark));
 assert(parse(h,&item) && item.mark.v==7 && item.mark.m==255);
 assert(parse(sa(OWN_ID,OWN_ID),&item) && !item.policy && item.id.sa.spi==0x1234);
 assert(!parse(sa(OWN_ID,99),&item));assert(!parse(sa(99,OWN_ID),&item));assert(!parse(sa(OWN_ID,0),&item));
 pid_t child=fork();assert(child>=0);
 if(!child){freopen("/dev/null","w",stderr);h=sa(OWN_ID,OWN_ID);h->nlmsg_len=NLMSG_LENGTH(1);parse(h,&item);_exit(0);}
 int status;assert(waitpid(child,&status,0)==child);assert(WIFEXITED(status) && WEXITSTATUS(status)==1);
 puts("PASS: both ownership IDs, mixed templates, marks, SA identity and truncated-message refusal");return 0;
}
