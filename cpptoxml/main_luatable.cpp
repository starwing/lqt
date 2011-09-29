/*
 * Copyright 2009 Mauro Iazzi <mauro.iazzi@gmail.com>
 * Copyright 2009 Peter Kümmel <syntheticpp@gmx.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 */


#include <iostream>
#include <typeinfo>

#include "binder.h"
#include "codemodel.h"
#include "control.h"
#include "parser.h"
#include "preprocessor.h"

#include <QByteArray>
#include <QFile>
#include <QTextCodec>
#include <QTextStream>

#include <QObject>
#include <QDir>

#include <QDebug>


#define INDENT ( QString(indent*2, ' ') )
#define ATTR_STR(n, v) ( INDENT + escape_chars(v).prepend(n " = \"").append("\",\n") )
#define ATTR_OBJ(n, v) ( INDENT + v.prepend(n " = ").append(",\n") )
#define ATTR_NUM(n, v) ( INDENT + (QString::number(v)).prepend(n " = ").append(",\n") )
#define ATTR_TRUE(n) ( INDENT + n + QString(" = true,\n") )


using namespace std;

QString escape_chars(QString s)
{
    QString ret = s;
    ret.replace('"', "\\\"");
    ret.replace('\'', "\\\\");
    return ret;
}

class LuaTableVisitor
{
private:
    bool resolve_types;
    QString current_id;
    QStringList current_context;
    QList<CodeModelItem> current_scope;
    CodeModelItem outer_scope;
    int indent;
public:
    LuaTableVisitor(CodeModelItem c, bool r = true):
        resolve_types(r), current_scope(), outer_scope(c), indent(0)
    {
        current_scope << c;
    }
    QString LuaTag(CodeModelItem);
    TypeInfo solve(const TypeInfo&, QStringList);
    TypeInfo simplifyType(TypeInfo const &, CodeModelItem __scope);
    QString visit(const TypeInfo&, QStringList);
    QString visit(CodeModelItem);
    /*
       template <typename T> QString visit(T) {
       std::cerr << "unimplemented CodeModelItem: " << typeid(T).name() << std::endl;
       return "";
       }
       */
};


TypeInfo LuaTableVisitor::simplifyType(TypeInfo const &__type, CodeModelItem __scope)
{
    CodeModel *__model = __scope->model();
    Q_ASSERT(__model != 0);
    TypeInfo t;
    for (int i = 0; i < __type.qualifiedName().size(); i++)
    {
        QStringList qname = t.qualifiedName();
        qname << __type.qualifiedName().at(i);
        t.setQualifiedName(qname);
        //t = this->solve(t, __scope->qualifiedName());
        QString oldt = t.toString();
        t = t.resolveType(t, __scope);
        if (t.toString() != oldt) qDebug() << oldt << " --> " << t.toString();
    }

    TypeInfo otherType = __type;
    otherType.setQualifiedName(t.qualifiedName());

    return otherType;
}



TypeInfo LuaTableVisitor::solve(const TypeInfo& t, QStringList scope)
{
    (void)scope;
    if (!resolve_types) return t;
    TypeInfo tt(t);
    for (QList<CodeModelItem>::const_iterator i = current_scope.begin();
            i < current_scope.end();
            i++)
    {
        TypeInfo ttt = tt;
        //qDebug() << tt.toString() << ttt.toString();
        Q_ASSERT(ttt == tt);
        do
        {
            tt = ttt;
            ttt = ttt.resolveType(tt, *i);
        }
        while (ttt != tt);

    }
    return tt;
}

QString attrStringList(QStringList list, int indent = 0)
{
    QString ret;
    if (!list.isEmpty())
    {
        ret += "{\n";
        ++indent;
        foreach(QString p, list)
            ret += p.prepend(INDENT + "\"").append("\",\n");
        --indent;
        ret += INDENT + "}";
    }
    return ret;
}

QString LuaTableVisitor::visit(const TypeInfo& t, QStringList scope)
{
    //t = t.resolveType(t, t.scope());

    QString oldt = t.toString();
    TypeInfo tt = solve(t, scope);
    //tt = simplifyType(tt, current_scope.first());
    while (oldt != tt.toString())
    {
        oldt = tt.toString();
        tt = solve(tt, scope);
    }
    //if (oldt!=tt.toString()) qDebug() << oldt << " -> " << tt.toString();

    QString ret;
    ret += ATTR_STR("type_name", tt.toString().replace(">>", "> >"));
    ret += ATTR_STR("type_base", tt.qualifiedName().join("::").replace(">>", "> >"));
    if (tt.isConstant()) ret += ATTR_TRUE("type_constant");
    if (tt.isVolatile()) ret += ATTR_TRUE("type_volatile");
    if (tt.isReference()) ret += ATTR_TRUE("type_reference");
    if (tt.indirections() > 0) ret += ATTR_NUM("indirections", tt.indirections());

    if (!tt.arrayElements().isEmpty())
        ret += ATTR_OBJ("array", attrStringList(tt.arrayElements(), indent));

    if (tt.isFunctionPointer()) ret += ATTR_TRUE("function_pointer");

    return ret;
}

#define TAG_CASE(s) case _CodeModelItem::Kind_##s: return #s

QString LuaTableVisitor::LuaTag(CodeModelItem i)
{
    switch (i->kind())
    {
        TAG_CASE(Scope);
        TAG_CASE(Namespace);
        TAG_CASE(Member);
        TAG_CASE(Function);
        TAG_CASE(Argument);
        TAG_CASE(Class);
        TAG_CASE(Enum);
        TAG_CASE(Enumerator);
        TAG_CASE(File);
        TAG_CASE(FunctionDefinition);
        TAG_CASE(TemplateParameter);
        TAG_CASE(TypeAlias);
        TAG_CASE(Variable);
    }
    return QString();
}

QString templateParametersToList(TemplateParameterList list, int indent = 0)
{
    QString ret;
    QStringList nameList;
    foreach(TemplateParameterModelItem p, list)
        nameList << p->name();
    return attrStringList(nameList, indent);
}

QString LuaTableVisitor::visit(CodeModelItem i)
{
    QString ret;

    ++indent;
    ret += ATTR_STR("type", LuaTag(i));

    current_id = LuaTag(i) + " => " + i->qualifiedName().join("::"); // FIXME: this is debug code

    ret += ATTR_NUM("id", i->creationId());
    ret += ATTR_STR("name", i->name());
    ret += ATTR_STR("scope", i->scope().join("::"));
    ret += ATTR_STR("context", current_context.join("::"));
    // FIXME: is this a dirty hack? yes, it is!
    if (ArgumentModelItem a = model_dynamic_cast<ArgumentModelItem>(i))
    {
        //ret += ATTR_STR("fullname", current_context.join("::")+"::"+i->qualifiedName().join("::"));
    }
    else if (EnumeratorModelItem a = model_dynamic_cast<EnumeratorModelItem>(i))
    {
        ret += ATTR_STR("fullname", current_context.join("::") + "::" + i->qualifiedName().join("::"));
    }
    else
    {
        ret += ATTR_STR("fullname", i->qualifiedName().join("::"));
    }

    if (MemberModelItem m = model_dynamic_cast<MemberModelItem>(i))
    {
        if (m->isConstant()) ret += ATTR_TRUE("constant");
        if (m->isVolatile()) ret += ATTR_TRUE("volatile");
        if (m->isStatic()) ret += ATTR_TRUE("static");
        if (m->isAuto()) ret += ATTR_TRUE("auto");
        if (m->isFriend()) ret += ATTR_TRUE("friend");
        if (m->isRegister()) ret += ATTR_TRUE("register");
        if (m->isExtern()) ret += ATTR_TRUE("extern");
        if (m->isMutable()) ret += ATTR_TRUE("mutable");
        QStringList ownerName = m->qualifiedName();
        ownerName.pop_back();
        ret += ATTR_STR("member_of", ownerName.join("::"));

        if (ClassModelItem c = model_dynamic_cast<ClassModelItem>(current_scope.last()))
            ret += ATTR_STR("member_of_class", c->qualifiedName().join("::"));

        switch (m->accessPolicy())
        {
        case CodeModel::Public:
            ret += ATTR_STR("access", "public");
            break;
        case CodeModel::Private:
            ret += ATTR_STR("access", "private");
            break;
        case CodeModel::Protected:
            ret += ATTR_STR("access", "protected");
            break;
        };

        ret += visit(m->type(), m->scope());
        if (!m->templateParameters().isEmpty())
        {
            QString tp = templateParametersToList(m->templateParameters(), indent);
            ret += ATTR_OBJ("member_template_parameters", tp);
        }
    }
    if (FunctionModelItem f = model_dynamic_cast<FunctionModelItem>(i))
    {
        if (f->isVirtual()) ret += ATTR_TRUE("virtual");
        if (f->isInline()) ret += ATTR_TRUE("inline");
        if (f->isExplicit()) ret += ATTR_TRUE("explicit");
        if (f->isAbstract()) ret += ATTR_TRUE("abstract");
        if (f->isVariadics()) ret += ATTR_TRUE("variadics");
        //if (i->name()=="destroyed") qDebug() << CodeModel::Normal << CodeModel::Slot << CodeModel::Signal << m->functionType() << i->qualifiedName();
        switch (f->functionType())
        {
        case CodeModel::Normal:
            break;
        case CodeModel::Slot:
            ret += ATTR_TRUE("slot");
            break;
        case CodeModel::Signal:
            ret += ATTR_TRUE("signal");
            break;
        }
    }
    if (ArgumentModelItem a = model_dynamic_cast<ArgumentModelItem>(i))
    {
        ret += visit(a->type(), a->scope());
        if (a->defaultValue())
        {
            ret += ATTR_TRUE("default");
            ret += ATTR_STR("defaultvalue", a->defaultValueExpression());
        }
    }
    if (ClassModelItem c = model_dynamic_cast<ClassModelItem>(i))
    {
        switch (c->accessPolicy())
        {
        case CodeModel::Public:
            ret += ATTR_STR("access", "public");
            break;
        case CodeModel::Private:
            ret += ATTR_STR("access", "private");
            break;
        case CodeModel::Protected:
            ret += ATTR_STR("access", "protected");
            break;
        };

        if (!c->baseClasses().isEmpty())
        {
            QStringList fullBases;

            Q_ASSERT(c->baseClasses().size() == c->baseModifiers().size());
            for (int j = 0; j < c->baseClasses().size(); j++)
                fullBases.append(c->baseModifiers().at(j) + " " + c->baseClasses().at(j));

            ret += ATTR_OBJ("bases", attrStringList(c->baseClasses(), indent));
            ret += ATTR_OBJ("bases_with_attributes", attrStringList(fullBases, indent));
        }
        switch (c->classType())
        {
        case CodeModel::Class:
            ret += ATTR_STR("class_type", QString("class"));
            break;
        case CodeModel::Struct:
            ret += ATTR_STR("class_type", QString("struct"));
            break;
        case CodeModel::Union:
            ret += ATTR_STR("class_type", QString("union"));
            break;
        }
        if (!c->templateParameters().isEmpty())
        {
            QString tp = templateParametersToList(c->templateParameters(), indent);
            ret += ATTR_OBJ("member_template_parameters", tp);
        }

        // TODO also list propertyDeclarations (maybe in content?)
    }
    if (EnumModelItem e = model_dynamic_cast<EnumModelItem>(i))
    {
        switch (e->accessPolicy())
        {
        case CodeModel::Public:
            ret += ATTR_STR("access", "public");
            break;
        case CodeModel::Private:
            ret += ATTR_STR("access", "private");
            break;
        case CodeModel::Protected:
            ret += ATTR_STR("access", "protected");
            break;
        };
    }
    if (EnumeratorModelItem e = model_dynamic_cast<EnumeratorModelItem>(i))
    {
        ret += ATTR_STR("value", e->value());
    }
    if (TypeAliasModelItem t = model_dynamic_cast<TypeAliasModelItem>(i))
    {
        ret += visit(t->type(), t->scope());
    }

    //
    // content of the entry:
    //  - Arguments of functions
    //  - members of scopes
    //  - enumeration values
    //
    QString children;
    if (NamespaceModelItem n = model_dynamic_cast<NamespaceModelItem>(i))
    {
        foreach(NamespaceModelItem m, n->namespaces())
            children += visit(model_static_cast<CodeModelItem>(m)) + ",\n";
    }
    if (i->kind() & _CodeModelItem::Kind_Scope)
    {
        //qDebug() << ID_STR(i) << i->name() << current_context;
        //CodeModelItem os = current_scope; // save old outer scope
        if (!i->name().isEmpty())
        {
            current_context << i->name();
            current_scope << i;
        }
        ScopeModelItem s = model_dynamic_cast<ScopeModelItem>(i);

        foreach(ClassModelItem n, s->classes())
            children += visit(model_static_cast<CodeModelItem>(n)) + ",\n";
        foreach(EnumModelItem n, s->enums())
            children += visit(model_static_cast<CodeModelItem>(n)) + ",\n";
        foreach(FunctionModelItem n, s->functions())
            children += visit(model_static_cast<CodeModelItem>(n)) + ",\n";
        foreach(TypeAliasModelItem n, s->typeAliases())
            children += visit(model_static_cast<CodeModelItem>(n)) + ",\n";
        foreach(VariableModelItem n, s->variables())
            children += visit(model_static_cast<CodeModelItem>(n)) + ",\n";

        if (!i->name().isEmpty())
        {
            current_context.removeLast();
            current_scope.pop_back();
        }
    }
    if (FunctionModelItem f = model_dynamic_cast<FunctionModelItem>(i))
    {
        foreach(ArgumentModelItem a, f->arguments())
            children += visit(model_static_cast<CodeModelItem>(a)) + ",\n";
    }
    if (EnumModelItem e = model_dynamic_cast<EnumModelItem>(i))
    {
        QString last = QChar('0');
        foreach(EnumeratorModelItem n, model_dynamic_cast<EnumModelItem>(i)->enumerators())
        {
            if (n->value() == QString())
                n->setValue(last.append("+1")); //FIXME: Is there a reason for not putting the value itself? :S
            children += visit(model_static_cast<CodeModelItem>(n)) + ",\n";
            last = n->value();
        }
    }

    --indent;

    return INDENT + "{\n" + ret + children + INDENT + "}";
}

void printHelp(const char* progname)
{
    const char* help =
        "Usage: %s <flags> <file>\n\n"
        "Options:\n"
        "<file> file to parse\n"
        "-C     add a config file\n"
        "-D     define a macro on command line\n"
        "-U     undefine a macro on command line\n"
        "-E     only preprocess\n"
        "-R     don't resolve\n"
        "-N     generate NO code\n"
        "-v     verbose\n"
        "-d     debug\n"
        "-h     print this help\n"
        "-I     Add another include directory\n"
        "-o     output file\n"
        ;
    fprintf(stderr, help, QFileInfo(progname).fileName().toAscii().data());
}

void WriteFile(QString outputFile, QString contents) {
    if (outputFile.isEmpty() || outputFile == "-")
    {
        QTextStream(stdout) << contents;
    }
    else
    {
        QFile file(outputFile);
        if (file.open(QFile::WriteOnly | QFile::Text))
        {
            file.write(contents.toLatin1());
        }
    }
}

int main(int argc, char **argv)
{
    bool onlyPreprocess = false;
    bool dontResolve = false;
    bool noCode = false;
    bool verbose = false;
    bool debug = false;
    QStringList configNames;
    QStringList inclist;
    QStringList macros;
    QString sourceName;
    QString outputFile;

    for (int i = 1; i < argc; i++)
    {
        if (argv[i][0] != '-' || argv[i][1] == 0)
        {
            sourceName = QString::fromLatin1(argv[i]);
            continue;
        }

        QString argValue;
        bool separed = (argv[i][2] == '\0' && argc > i + 1 && argv[i+1][0] != '-');
        if (separed)
            argValue = QDir::fromNativeSeparators(QString::fromLatin1(argv[i+1]).right(strlen(argv[i+1])));
        else
            argValue = QDir::fromNativeSeparators(QString::fromLatin1(argv[i]).right(strlen(argv[i]) - 2));

        switch (argv[i][1])
        {
        case 'E':
            onlyPreprocess = true;
            break;
        case 'R':
            dontResolve = true;
            break;
        case 'N':
            noCode = true;
            break;
        case 'v':
            verbose = true;
            break;
        case 'd':
            debug = true;
            break;
        case 'h':
            printHelp(argv[0]);
            return 0;
        case 'I':
            inclist.append(argValue);
            if (separed) ++i;
            break;
        case 'C':
            configNames.append(argValue);
            if (separed) ++i;
            break;
        case 'o':
            outputFile = argValue;
            if (separed) ++i;
            break;
        case 'D':
            macros.append("-D" + argValue);
            if (separed) ++i;
            break;
        case 'U':
            macros.append("-U" + argValue);
            if (separed) ++i;
            break;

        default:
            fprintf(stderr, "found unknown parameter: %s", argv[i]);
            return 1;
        }
    }

    if (sourceName.isEmpty())
    {
        printHelp(argv[0]);
        return 0;
    }

    if (verbose) fprintf(stderr, "Used file: %s\n\n", qPrintable(sourceName));

    Preprocessor pp;

    foreach (QString configName, configNames) {
        pp.processFile(configName);
    }

    QStringList sourceInclist;
    QFileInfo sourceInfo(sourceName);
    sourceInclist.append(sourceInfo.absolutePath());
    pp.addIncludePaths(sourceInclist);
    pp.addIncludePaths(inclist);
    pp.addMacros(macros);

    pp.processFile(sourceName);
    QByteArray contents = pp.result();

    if (debug) qDebug() << pp.macroNames();
    if (debug) qDebug() << contents;
    if (debug) QTextStream(stdout) << contents;

    if (onlyPreprocess)
    {
        WriteFile(outputFile, contents);
        return 0;
    }

    Control control;
    Parser p(&control);
    pool __pool;

    TranslationUnitAST *ast = p.parse(contents, contents.size(), &__pool);

    CodeModel model;
    Binder binder(&model, p.location());
    FileModelItem f_model = binder.run(ast);

    if (!noCode)
    {
        LuaTableVisitor visitor((CodeModelItem)f_model, !dontResolve);
        QString luaTable = visitor.visit(model_static_cast<CodeModelItem>(f_model));
        WriteFile(outputFile, luaTable);
    }

    return 0;
}

