
## http://aspn.activestate.com/ASPN/Cookbook/Python/Recipe/364469
import compiler

class Unsafe_Source_Error(Exception):
    def __init__(self,error,descr = None,node = None):
        self.error = error
        self.descr = descr
        self.node = node
        self.lineno = getattr(node,"lineno",None)
        
    def __repr__(self):
        return "Line %d.  %s: %s" % (self.lineno, self.error, self.descr)
    __str__ = __repr__    
           
class SafeEval(object):
    
    def visit(self, node,**kw):
        cls = node.__class__
        meth = getattr(self,'visit'+cls.__name__,self.default)
        return meth(node, **kw)
            
    def default(self, node, **kw):
        for child in node.getChildNodes():
            return self.visit(child, **kw)
            
    visitExpression = default
    
    def visitConst(self, node, **kw):
        return node.value

    def visitDict(self,node,**kw):
        return dict([(self.visit(k),self.visit(v)) for k,v in node.items])
        
    def visitTuple(self,node, **kw):
        return tuple(self.visit(i) for i in node.nodes)
        
    def visitList(self,node, **kw):
        return [self.visit(i) for i in node.nodes]

    def visitUnarySub(self, node, **kw):
        return - self.visit (node.getChildNodes ()[0])

class SafeEvalWithErrors(SafeEval):

    def default(self, node, **kw):
        raise Unsafe_Source_Error("Unsupported source construct",
                                node.__class__,node)
            
    def visitName(self,node, **kw):
        raise Unsafe_Source_Error("Strings must be quoted", 
                                 node.name, node)
                                 
    # Add more specific errors if desired
            

def safe_eval(source, fail_on_error = True):
    walker = fail_on_error and SafeEvalWithErrors() or SafeEval()
    try:
        ast = compiler.parse(source,"eval")
    except SyntaxError, err:
        raise
    try:
        return walker.visit(ast)
    except Unsafe_Source_Error, err:
        raise


def safe_eval(source, fail_on_error = True):
    walker = fail_on_error and SafeEvalWithErrors() or SafeEval()
    try:
        ast = compiler.parse(source,"eval")
    except SyntaxError, err:
        raise
    try:
        return walker.visit(ast)
    except Unsafe_Source_Error, err:
        raise

def test ():
    print safe_eval ('{1: [2,3], "4": (-1,2)}')
    
if __name__ == '__main__':
    test ()
